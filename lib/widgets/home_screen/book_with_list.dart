import '../../models/book.dart';

class BookWithList {
  final Book book;
  final String listId;
  final String listName;

  BookWithList({
    required this.book,
    required this.listId,
    required this.listName,
  });
}
