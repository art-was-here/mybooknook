import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/book.dart';

class DatabaseService {
  static Database? _database;
  static const Duration _cacheExpiry = Duration(hours: 1);

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initializeDatabase();
    return _database!;
  }

  Future<Database> _initializeDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'mybooknook.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE books(
            id TEXT PRIMARY KEY,
            title TEXT,
            authors TEXT,
            description TEXT,
            imageUrl TEXT,
            isbn TEXT,
            publishedDate TEXT,
            publisher TEXT,
            pageCount INTEGER,
            categories TEXT,
            tags TEXT,
            listId TEXT,
            listName TEXT,
            userId TEXT,
            createdAt TEXT,
            lastUpdated TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE lists(
            id TEXT PRIMARY KEY,
            name TEXT,
            createdAt TEXT,
            lastUpdated TEXT
          )
        ''');
      },
    );
  }

  Future<void> ensureIndexes() async {
    final db = await database;
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_books_isbn ON books(isbn)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_books_listId ON books(listId)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_lists_name ON lists(name)');
  }

  Future<void> cacheBook(
      Book book, String listId, String listName, String userId) async {
    final db = await database;
    final now = DateTime.now();
    final bookData = {
      'id': book.isbn,
      'title': book.title,
      'authors': book.authors?.join(','),
      'description': book.description ?? '',
      'imageUrl': book.imageUrl,
      'isbn': book.isbn,
      'publishedDate': book.publishedDate,
      'publisher': book.publisher,
      'pageCount': book.pageCount,
      'categories': book.categories?.join(','),
      'tags': book.tags?.join(','),
      'listId': listId,
      'listName': listName,
      'userId': userId,
      'createdAt': now.toIso8601String(),
      'lastUpdated': now.toIso8601String(),
    };

    await db.insert(
      'books',
      bookData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Book?> getCachedBook(String isbn) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'books',
      where: 'isbn = ?',
      whereArgs: [isbn],
    );

    if (maps.isEmpty) return null;

    final data = maps.first;
    return Book(
      title: data['title'] as String,
      authors: (data['authors'] as String?)?.split(','),
      description: data['description'] as String? ?? '',
      imageUrl: data['imageUrl'] as String?,
      isbn: data['isbn'] as String,
      publishedDate: data['publishedDate'] as String?,
      publisher: data['publisher'] as String?,
      pageCount: data['pageCount'] as int?,
      categories: (data['categories'] as String?)?.split(','),
      tags: (data['tags'] as String?)?.split(','),
    );
  }

  Future<void> clearExpiredCache() async {
    final db = await database;
    final expiryTime = DateTime.now().subtract(_cacheExpiry).toIso8601String();
    await db.delete(
      'books',
      where: 'lastUpdated < ?',
      whereArgs: [expiryTime],
    );
  }
}
