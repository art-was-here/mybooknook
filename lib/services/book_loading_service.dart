import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/book.dart';
import '../widgets/home_screen/book_with_list.dart';
import 'book_cache_service.dart';
import 'database_service.dart';

class BookLoadingService {
  final BookCacheService _bookCacheService;
  final DatabaseService _databaseService;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  BookLoadingService({
    required BookCacheService bookCacheService,
    required DatabaseService databaseService,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _bookCacheService = bookCacheService,
        _databaseService = databaseService,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  Future<List<BookWithList>> loadBooks(String listId) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final booksSnapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .doc(listId)
          .collection('books')
          .get();

      final List<BookWithList> books = [];
      final listDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .doc(listId)
          .get();

      final listName = listDoc.data()?['name'] as String? ?? 'Unknown List';

      for (final doc in booksSnapshot.docs) {
        final bookData = doc.data();
        final isbn = bookData['isbn'] as String?;

        if (isbn == null) continue;

        // Try to get from cache first
        Book? book = _bookCacheService.getCachedBook(isbn);

        if (book == null) {
          // Try to get from SQLite cache
          book = await _databaseService.getCachedBook(isbn);

          if (book != null) {
            // Update in-memory cache
            _bookCacheService.cacheBook(book);
          } else {
            // Load from Firestore
            book = Book.fromMap(bookData);
            _bookCacheService.cacheBook(book);
            await _databaseService.cacheBook(book, listId, listName, user.uid);
          }
        }

        books.add(BookWithList(
          book: book,
          listId: listId,
          listName: listName,
        ));
      }

      return books;
    } catch (e) {
      print('Error loading books: $e');
      return [];
    }
  }

  Future<void> clearCache() async {
    _bookCacheService.clearAllCache();
    await _databaseService.clearExpiredCache();
  }
}
