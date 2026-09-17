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
  static Future<Database>? _readOnlyDatabaseFuture;

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 11,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.rawQuery('PRAGMA busy_timeout = 3000');
        final walResult = await db.rawQuery('PRAGMA journal_mode = WAL');
        final mode = walResult.isNotEmpty
            ? walResult.first.values.first.toString().toLowerCase()
            : null;
        if (mode != 'wal') {
          throw StateError(
            'Failed to enable WAL journal mode (got "$mode" instead) — '
                'the read-only connection depends on WAL for concurrent reads.',
          );
        }
      },
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<Database> get readOnlyDatabase {
    if (_readOnlyDatabase != null) return Future.value(_readOnlyDatabase!);
    return _readOnlyDatabaseFuture ??= _openReadOnlyDatabase();
  }

  Future<Database> _openReadOnlyDatabase() async {
    await database;
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'tumpang_cache.db');
    _readOnlyDatabase = await openDatabase(path, readOnly: true, singleInstance: false);
    await _readOnlyDatabase!.rawQuery('PRAGMA busy_timeout = 3000');
    return _readOnlyDatabase!;
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
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
      await db.execute('ALTER TABLE payments ADD COLUMN payment_intent_id TEXT');
    }

    if (oldVersion < 9) {
      await db.execute('ALTER TABLE payments ADD COLUMN platform_fee REAL');
      await db.execute('ALTER TABLE payments ADD COLUMN driver_net_amount REAL');
      await db.execute('ALTER TABLE payout_settings ADD COLUMN platform_fee REAL NOT NULL DEFAULT 1.00');
    }

    if (oldVersion < 10) {
      await db.execute('ALTER TABLE payments ADD COLUMN credited_to_driver_at TEXT');
    }

    if (oldVersion < 11) {
      await _createDriverWalletTripsTable(db);
    }
  }

  Future<void> _createDB(Database db, int version) async {
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
      CREATE TABLE payout_settings (
        id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
        bank_transfer_fee REAL NOT NULL DEFAULT 1.00,
        platform_fee REAL NOT NULL DEFAULT 1.00
      )
    ''');

    await _createPostSignupDraftTable(db);
    await _createPendingPayoutReconciliationTable(db);
    await _createDriverWalletTripsTable(db);
  }

  Future<void> _createDriverWalletTripsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS driver_wallet_trips (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        passenger_name TEXT,
        trip_name TEXT,
        pickup_name TEXT,
        dropoff_name TEXT,
        points REAL,
        gross_amount REAL,
        platform_fee REAL,
        daily_fee REAL,
        cycle_start_date TEXT,
        cycle_end_date TEXT,
        paid_at TEXT,
        in_month INTEGER NOT NULL DEFAULT 0,
        is_recent INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_driver_wallet_trips_user '
          'ON driver_wallet_trips (user_id, paid_at DESC)',
    );
  }

  Future<void> _createPendingPayoutReconciliationTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_payout_reconciliation (
        payout_id TEXT PRIMARY KEY,
        status TEXT NOT NULL CHECK (status IN ('completed', 'failed')),
        created_at TEXT NOT NULL
      )
    ''');
  }

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