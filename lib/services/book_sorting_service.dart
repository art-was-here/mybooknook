import '../models/book.dart';
import '../widgets/home_screen/book_with_list.dart';

class BookSortingService {
  static const String _defaultSortPreference = 'title';

  String _sortPreference = _defaultSortPreference;

  String get sortPreference => _sortPreference;

  void setSortPreference(String preference) {
    _sortPreference = preference;
  }

  List<BookWithList> sortBooks(List<BookWithList> books) {
    switch (_sortPreference) {
      case 'title':
        return _sortByTitle(books);
      case 'author':
        return _sortByAuthor(books);
      case 'date':
        return _sortByDate(books);
      default:
        return _sortByTitle(books);
    }
  }

  List<BookWithList> _sortByTitle(List<BookWithList> books) {
    books.sort((a, b) => a.book.title.compareTo(b.book.title));
    return books;
  }

  List<BookWithList> _sortByAuthor(List<BookWithList> books) {
    books.sort((a, b) {
      final authorA = a.book.authors?.firstOrNull ?? '';
      final authorB = b.book.authors?.firstOrNull ?? '';
      return authorA.compareTo(authorB);
    });
    return books;
  }

  List<BookWithList> _sortByDate(List<BookWithList> books) {
    books.sort((a, b) {
      final dateA = a.book.publishedDate ?? '';
      final dateB = b.book.publishedDate ?? '';
      return dateB.compareTo(dateA); // Most recent first
    });
    return books;
  }
}
