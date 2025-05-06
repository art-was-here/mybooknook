import '../models/book.dart';

class BookCacheService {
  final Map<String, Book> _bookCache = {};
  final Map<String, DateTime> _bookCacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(hours: 1);

  Book? getCachedBook(String isbn) {
    final cachedBook = _bookCache[isbn];
    final cacheTime = _bookCacheTimestamps[isbn];

    if (cachedBook != null && cacheTime != null) {
      if (DateTime.now().difference(cacheTime) < _cacheExpiry) {
        return cachedBook;
      } else {
        // Remove expired cache entry
        _bookCache.remove(isbn);
        _bookCacheTimestamps.remove(isbn);
      }
    }
    return null;
  }

  void cacheBook(Book book) {
    final now = DateTime.now();
    _bookCache[book.isbn] = book;
    _bookCacheTimestamps[book.isbn] = now;
  }

  void removeBook(String isbn) {
    _bookCache.remove(isbn);
    _bookCacheTimestamps.remove(isbn);
  }

  void clearExpiredCache() {
    final now = DateTime.now();
    final expiredKeys = _bookCacheTimestamps.entries
        .where((entry) => now.difference(entry.value) > _cacheExpiry)
        .map((entry) => entry.key)
        .toList();

    for (final key in expiredKeys) {
      _bookCache.remove(key);
      _bookCacheTimestamps.remove(key);
    }
  }

  void clearAllCache() {
    _bookCache.clear();
    _bookCacheTimestamps.clear();
  }
}
