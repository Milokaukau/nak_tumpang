import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDbService {
  // Singleton pattern to prevent opening multiple connections
  static final LocalDbService instance = LocalDbService._init();
  static Database? _database;

  LocalDbService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('tumpang_cache.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // We will define specific tables later.
    // This is just a dummy table to test the connection.
    await db.execute('''
      CREATE TABLE test_connection (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT NOT NULL
      )
    ''');
  }

  Future<void> testConnection() async {
    final db = await instance.database;
    print('✅ SQLite connected successfully at: ${db.path}');
  }
}