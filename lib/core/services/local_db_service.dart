import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDbService {
  static final LocalDbService instance = LocalDbService._init();
  static Database? _database;

  LocalDbService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tumpang_cache.db');
    return _database!;
  }

  static Database? _readOnlyDatabase;

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 10,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  /// A second handle onto the same file, opened read-only at the SQLite
  /// engine level. This is the mirror of the Supabase-side RLS lockdown on
  /// driver_profiles/payout_history/payout_settings (view-only from the
  /// client; every write goes through settle_payments()/request_payout()):
  /// nothing that only needs to *display* cached wallet/trip data should be
  /// able to write to this database file, even by accident. Local services'
  /// `get*`/`getCached*` methods should use this getter; only the `cache*`/
  /// `save*`/`clear*` methods that mirror a successful Supabase round-trip
  /// should use the writable [database] getter above.
  ///
  /// Must be opened after the writable connection has run migrations at
  /// least once (a read-only handle can't create or upgrade the schema),
  /// which `database` above guarantees since it's always awaited first.
  Future<Database> get readOnlyDatabase async {
    if (_readOnlyDatabase != null) return _readOnlyDatabase!;
    await database; // ensure the file exists and is migrated
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tumpang_cache.db');
    _readOnlyDatabase = await openDatabase(path, readOnly: true);
    return _readOnlyDatabase!;
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Widen points_ledger's reason CHECK to match the Supabase migration
      // (added 'goyang_points'/'goyang_voucher'). SQLite can't ALTER a
      // CHECK constraint in place, so rename the old table, create the new
      // one with the updated constraint, copy the existing rows across,
      // then drop the old table — preserves cached history instead of
      // wiping it on upgrade.
      await db.execute('ALTER TABLE points_ledger RENAME TO points_ledger_old');

      await db.execute('''
      CREATE TABLE points_ledger (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        change_amount INTEGER NOT NULL,
        reason TEXT NOT NULL CHECK (reason IN ('trip_completed', 'voucher_redeemed', 'goyang_points', 'goyang_voucher')),
        reference_id TEXT,
        description TEXT NOT NULL,
        created_at TEXT,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

      await db.execute('''
      INSERT INTO points_ledger (id, user_id, change_amount, reason, reference_id, description, created_at)
      SELECT id, user_id, change_amount, reason, reference_id, description, created_at
      FROM points_ledger_old
    ''');

      await db.execute('DROP TABLE points_ledger_old');
    }

    if (oldVersion < 3) {
      await _createPostSignupDraftTable(db);
    }

    if (oldVersion < 4) {
      // payout_history's local schema had drifted from what the app
      // actually reads/writes: it required a `payout_at` column that
      // nothing ever supplies (guaranteed NOT NULL failure on every
      // insert), required `bank_acc_no` even though e-wallet payouts
      // deliberately leave it null, and was missing `ewallet_phone`
      // entirely. That mismatch made every local cache write throw —
      // right after a successful request_payout() call, and right
      // after a successful history fetch — which is what made claim
      // payout look like it "failed" (the server-side payout had
      // already gone through) and made payout history fail to load.
      // Safe to just drop and recreate: this table is a pure read
      // cache of Supabase's payout_history, never the source of truth,
      // so it refills itself on the next successful fetch.
      await db.execute('DROP TABLE IF EXISTS payout_history');
      await db.execute('''
        CREATE TABLE payout_history (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          amount REAL NOT NULL,
          bank_name TEXT,
          bank_acc_no TEXT,
          ewallet_phone TEXT,
          status TEXT NOT NULL CHECK (status IN ('pending', 'completed', 'failed')),
          requested_at TEXT,
          processed_at TEXT,
          payment_method TEXT NOT NULL CHECK (payment_method IN ('bank_transfer', 'tng_ewallet')),
          fee REAL NOT NULL DEFAULT 0,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 5) {
      await _createPendingPayoutReconciliationTable(db);
    }

    if (oldVersion < 6) {
      // Re-apply the payout_history fix from the oldVersion < 4 block
      // above, unconditionally. Devices that had already reached
      // version 4 or 5 before that migration was added never ran it —
      // onUpgrade only fires for oldVersion < the declared version, so
      // their local payout_history table is still stuck with the
      // dropped payout_at column / missing ewallet_phone. Bumping the
      // version and redoing the drop-and-recreate here (safe: this
      // table is a pure read cache of Supabase's payout_history) makes
      // sure every device actually gets the corrected schema, not just
      // ones upgrading from a version older than 4.
      await db.execute('DROP TABLE IF EXISTS payout_history');
      await db.execute('''
        CREATE TABLE payout_history (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          amount REAL NOT NULL,
          bank_name TEXT,
          bank_acc_no TEXT,
          ewallet_phone TEXT,
          status TEXT NOT NULL CHECK (status IN ('pending', 'completed', 'failed')),
          requested_at TEXT,
          processed_at TEXT,
          payment_method TEXT NOT NULL CHECK (payment_method IN ('bank_transfer', 'tng_ewallet')),
          fee REAL NOT NULL DEFAULT 0,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 7) {
      // Correction to the oldVersion < 4/6 fix above, which *removed*
      // payout_at from this table on the theory that nothing supplied
      // it. That was wrong: Supabase's real payout_history table has
      // payout_at as a genuine NOT NULL column, and
      // PayoutService.fetchPayoutHistoryPage() does a bare .select(),
      // so every row fetched from the server legitimately includes a
      // payout_at key. PayoutLocalService.cachePayoutHistoryPage()
      // passes that row straight to db.insert(), so with the column
      // missing locally, EVERY successful online history fetch has been
      // failing to cache ever since v4 — not just the local
      // just-submitted-payout insert in PayoutViewModel.submitPayout()
      // (which never sets payout_at itself, hence nullable here).
      await db.execute('DROP TABLE IF EXISTS payout_history');
      await db.execute('''
        CREATE TABLE payout_history (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          amount REAL NOT NULL,
          payout_at TEXT,
          bank_name TEXT,
          bank_acc_no TEXT,
          ewallet_phone TEXT,
          status TEXT NOT NULL CHECK (status IN ('pending', 'completed', 'failed')),
          requested_at TEXT,
          processed_at TEXT,
          payment_method TEXT NOT NULL CHECK (payment_method IN ('bank_transfer', 'tng_ewallet')),
          fee REAL NOT NULL DEFAULT 0,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 8) {
      // Preventive fix, same class of bug as the payout_history saga
      // above: Supabase's real payments table has a payment_intent_id
      // text column (nullable) that this local cache table never had.
      // Nothing hits this today — PaymentViewModel.fetchAllPayments()
      // only ever caches Payment.toJson(), a hand-picked field set that
      // happens not to include payment_intent_id — but that's
      // incidental, not guaranteed: the moment any code path caches a
      // raw Supabase row for this table (a bare .select(), the same
      // mistake payout_history's fetch path made), every write would
      // throw "table payments has no column named payment_intent_id".
      // Adding it now, nullable, closes that gap before it's needed
      // rather than after.
      await db.execute('ALTER TABLE payments ADD COLUMN payment_intent_id TEXT');
    }

    if (oldVersion < 9) {
      // Mirrors the Supabase migration that added these to `payments` and
      // `payout_settings` (see supabase/migrations/xxxx_platform_fee_and_payout_functions.sql).
      // settle_payments() sets platform_fee/driver_net_amount server-side
      // when an invoice is paid; driver_net_amount is what PayoutViewModel
      // reads for "recent trips" points and the trip detail dialog's
      // breakdown. Nullable here for the same reason payment_intent_id is:
      // unsettled (paid_at IS NULL) rows never have these set.
      await db.execute('ALTER TABLE payments ADD COLUMN platform_fee REAL');
      await db.execute('ALTER TABLE payments ADD COLUMN driver_net_amount REAL');
      await db.execute('ALTER TABLE payout_settings ADD COLUMN platform_fee REAL NOT NULL DEFAULT 1.00');
    }

    if (oldVersion < 10) {
      // Supabase's `payments` table also carries `credited_to_driver_at`
      // (see supabase/sql/settle_payments.sql) — set alongside
      // platform_fee/driver_net_amount the moment settle_payments() marks
      // an invoice paid_at. Without this column here, any cache write that
      // passes through a raw settled-payment row (the same "bare .select()"
      // failure mode as payment_intent_id / platform_fee above) would throw
      // "table payments has no column named credited_to_driver_at". Kept
      // nullable for the same reason: unsettled rows never have it.
      await db.execute('ALTER TABLE payments ADD COLUMN credited_to_driver_at TEXT');
    }
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. users
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        phone TEXT NOT NULL,
        reward_points_bal INTEGER DEFAULT 0,
        role TEXT NOT NULL CHECK (role IN ('passenger', 'driver')),
        created_at TEXT,
        updated_at TEXT,
        status TEXT DEFAULT 'active',
        avatar_url TEXT,
        photo_url TEXT,
        license_url TEXT,
        license_number TEXT
      )
    ''');

    // 2. driver_profiles
    await db.execute('''
      CREATE TABLE driver_profiles (
        user_id TEXT PRIMARY KEY,
        total_earnings REAL DEFAULT 0.00,
        available_balance REAL CHECK (available_balance >= 0),
        total_withdrawn REAL DEFAULT 0.00,
        bank_name TEXT,
        bank_acc_no TEXT,
        updated_at TEXT,
        license_number TEXT,
        license_url TEXT,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // 3. payout_history
    await db.execute('''
      CREATE TABLE payout_history (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        amount REAL NOT NULL,
        payout_at TEXT,
        bank_name TEXT,
        bank_acc_no TEXT,
        ewallet_phone TEXT,
        status TEXT NOT NULL CHECK (status IN ('pending', 'completed', 'failed')),
        requested_at TEXT,
        processed_at TEXT,
        payment_method TEXT NOT NULL CHECK (payment_method IN ('bank_transfer', 'tng_ewallet')),
        fee REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // 4. passenger_trips
    await db.execute('''
      CREATE TABLE passenger_trips (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        trip_name TEXT NOT NULL,
        desired_pickup_time TEXT NOT NULL,
        desired_dropoff_time TEXT NOT NULL,
        pickup_lat REAL NOT NULL,
        pickup_lng REAL NOT NULL,
        pickup_name TEXT NOT NULL,
        dropoff_lat REAL NOT NULL,
        dropoff_lng REAL NOT NULL,
        dropoff_name TEXT NOT NULL,
        active_monday INTEGER DEFAULT 0,
        active_tuesday INTEGER DEFAULT 0,
        active_wednesday INTEGER DEFAULT 0,
        active_thursday INTEGER DEFAULT 0,
        active_friday INTEGER DEFAULT 0,
        active_saturday INTEGER DEFAULT 0,
        active_sunday INTEGER DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // 5. driver_trips
    await db.execute('''
      CREATE TABLE driver_trips (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        trip_name TEXT NOT NULL,
        depart_time TEXT NOT NULL,
        arrival_time TEXT NOT NULL,
        depart_lat REAL NOT NULL,
        depart_lng REAL NOT NULL,
        depart_name TEXT NOT NULL,
        arrival_lat REAL NOT NULL,
        arrival_lng REAL NOT NULL,
        arrival_name TEXT NOT NULL,
        active_monday INTEGER DEFAULT 0,
        active_tuesday INTEGER DEFAULT 0,
        active_wednesday INTEGER DEFAULT 0,
        active_thursday INTEGER DEFAULT 0,
        active_friday INTEGER DEFAULT 0,
        active_saturday INTEGER DEFAULT 0,
        active_sunday INTEGER DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // 6. tumpang_subscription
    await db.execute('''
      CREATE TABLE tumpang_subscription (
        id TEXT PRIMARY KEY,
        passenger_trip_id TEXT NOT NULL,
        driver_trip_id TEXT NOT NULL,
        pickup_lat REAL NOT NULL,
        pickup_lng REAL NOT NULL,
        pickup_location TEXT NOT NULL,
        dropoff_lat REAL NOT NULL,
        dropoff_lng REAL NOT NULL,
        dropoff_location TEXT NOT NULL,
        pickup_time TEXT NOT NULL,
        fee REAL NOT NULL CHECK (fee >= 0),
        deposit REAL NOT NULL CHECK (deposit >= 0),
        deposit_refunded INTEGER DEFAULT 0,
        subscription_start_date TEXT NOT NULL,
        subscription_end_date TEXT NOT NULL,
        status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
        ended_by TEXT CHECK (ended_by IN ('passenger', 'driver', 'system', 'natural')),
        ended_at TEXT,
        created_at TEXT,
        cancellation_reason TEXT,
        FOREIGN KEY (passenger_trip_id) REFERENCES passenger_trips (id) ON DELETE CASCADE,
        FOREIGN KEY (driver_trip_id) REFERENCES driver_trips (id) ON DELETE CASCADE
      )
    ''');

    // 7. tumpang_request
    await db.execute('''
      CREATE TABLE tumpang_request (
        id TEXT PRIMARY KEY,
        passenger_trip_id TEXT NOT NULL,
        driver_trip_id TEXT NOT NULL,
        status TEXT NOT NULL,
        pickup_lat REAL,
        pickup_lng REAL,
        pickup_name TEXT,
        pickup_requested_by TEXT,
        pickup_is_accepted INTEGER,
        dropoff_lat REAL,
        dropoff_lng REAL,
        dropoff_name TEXT,
        dropoff_requested_by TEXT,
        dropoff_is_accepted INTEGER,
        pickup_time TEXT,
        pickup_time_requested_by TEXT,
        pickup_time_is_accepted INTEGER,
        fee REAL,
        fee_requested_by TEXT,
        fee_is_accepted INTEGER,
        sub_start_date TEXT,
        sub_start_requested_by TEXT,
        sub_start_is_accepted INTEGER,
        sub_end_date TEXT,
        sub_end_requested_by TEXT,
        sub_end_is_accepted INTEGER,
        subscription_id TEXT,
        is_extension INTEGER DEFAULT 0,
        extends_subscription_id TEXT,
        extension_type TEXT,
        FOREIGN KEY (passenger_trip_id) REFERENCES passenger_trips (id) ON DELETE CASCADE,
        FOREIGN KEY (driver_trip_id) REFERENCES driver_trips (id) ON DELETE CASCADE,
        FOREIGN KEY (extends_subscription_id) REFERENCES tumpang_subscription (id) ON DELETE CASCADE
      )
    ''');

    // 8. payments
    await db.execute('''
      CREATE TABLE payments (
        id TEXT PRIMARY KEY,
        tumpang_subscription_id TEXT NOT NULL,
        month INTEGER NOT NULL,
        year INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        paid_at TEXT,
        amount REAL NOT NULL DEFAULT 0.00,
        cycle_start_date TEXT,
        cycle_end_date TEXT,
        payment_intent_id TEXT,
        platform_fee REAL,
        driver_net_amount REAL,
        credited_to_driver_at TEXT,
        FOREIGN KEY (tumpang_subscription_id) REFERENCES tumpang_subscription (id) ON DELETE CASCADE
      )
    ''');

    // 9. tumpang_trip_log
    await db.execute('''
      CREATE TABLE tumpang_trip_log (
        id TEXT PRIMARY KEY,
        tumpang_subscription_id TEXT NOT NULL,
        trip_date TEXT NOT NULL,
        completed_at TEXT,
        distance_km REAL CHECK (distance_km >= 0),
        status TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('completed', 'skipped_exception', 'no_show')),
        FOREIGN KEY (tumpang_subscription_id) REFERENCES tumpang_subscription (id) ON DELETE CASCADE
      )
    ''');

    // 10. reward_points
    await db.execute('''
      CREATE TABLE reward_points (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        obtained_points INTEGER NOT NULL CHECK (obtained_points > 0),
        avai_points INTEGER NOT NULL,
        obtained_at TEXT NOT NULL,
        expired_at TEXT NOT NULL,
        tumpang_trip_log_id TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // 11. tumpang_exception
    await db.execute('''
      CREATE TABLE tumpang_exception (
        id TEXT PRIMARY KEY,
        tumpang_subscription_id TEXT NOT NULL,
        initiated_by TEXT NOT NULL,
        initiated_by_role TEXT NOT NULL CHECK (initiated_by_role IN ('driver', 'passenger')),
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        reason TEXT,
        status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'cancelled')),
        FOREIGN KEY (initiated_by) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');

    // 12. vouchers
    await db.execute('''
      CREATE TABLE vouchers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        validity_days INTEGER NOT NULL CHECK (validity_days > 0),
        tnc TEXT,
        open_for_redeem INTEGER DEFAULT 1,
        req_points INTEGER NOT NULL CHECK (req_points > 0),
        stock_quantity INTEGER CHECK (stock_quantity >= 0)
      )
    ''');

    // 13. user_vouchers
    await db.execute('''
      CREATE TABLE user_vouchers (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        voucher_id TEXT NOT NULL,
        code TEXT NOT NULL UNIQUE,
        obtained_at TEXT NOT NULL,
        expired_at TEXT NOT NULL,
        used_at TEXT,
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
        FOREIGN KEY (voucher_id) REFERENCES vouchers (id) ON DELETE CASCADE
      )
    ''');

    // 14. points_ledger
    await db.execute('''
  CREATE TABLE points_ledger (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    change_amount INTEGER NOT NULL,
    reason TEXT NOT NULL CHECK (reason IN ('trip_completed', 'voucher_redeemed', 'goyang_points', 'goyang_voucher')),
    reference_id TEXT,
    description TEXT NOT NULL,
    created_at TEXT,
    FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
  )
''');

    // 15. payout_settings
    await db.execute('''
      CREATE TABLE payout_settings (
        id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
        bank_transfer_fee REAL NOT NULL DEFAULT 1.00,
        platform_fee REAL NOT NULL DEFAULT 1.00
      )
    ''');

    // 16. post_signup_draft
    await _createPostSignupDraftTable(db);

    // 17. pending_payout_reconciliation
    await _createPendingPayoutReconciliationTable(db);
  }

  // A payout whose terminal status ('completed'/'failed') was decided
  // locally (see PayoutViewModel.runPayoutStatusAnimation) but failed to
  // persist to Supabase's payout_history even after one retry. Survives
  // app restarts so the driver isn't stuck showing a status that never
  // made it to the server — see PayoutLocalService.savePendingReconciliation.
  Future<void> _createPendingPayoutReconciliationTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_payout_reconciliation (
        payout_id TEXT PRIMARY KEY,
        status TEXT NOT NULL CHECK (status IN ('completed', 'failed')),
        created_at TEXT NOT NULL
      )
    ''');
  }

  // No longer written to — the post-signup driver flow now reuses
  // AddEditTripScreen (see add_edit_trip_screen.dart) instead of its
  // own screen/draft-saving view model, so nothing populates this
  // table anymore. Left in place rather than dropped so upgrading
  // installs that still have an old cached draft row don't hit a
  // "no such table" error before this comment is next revisited.
  Future<void> _createPostSignupDraftTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS post_signup_draft (
        user_id TEXT PRIMARY KEY,
        from_label TEXT,
        from_lat REAL,
        from_lng REAL,
        to_label TEXT,
        to_lat REAL,
        to_lng REAL,
        from_day INTEGER,
        to_day INTEGER,
        depart_hour INTEGER,
        depart_minute INTEGER,
        arrive_hour INTEGER,
        arrive_minute INTEGER,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> testConnection() async {
    final db = await instance.database;
    print('SQLite connected at: ${db.path}');
  }
}