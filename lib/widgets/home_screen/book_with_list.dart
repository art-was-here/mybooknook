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

  Map<String, dynamic> toJson() {
    return {
      'book': book.toMap(),
      'listId': listId,
      'listName': listName,
    };
  }

  factory BookWithList.fromJson(Map<String, dynamic> json) {
    return BookWithList(
      book: Book.fromMap(json['book']),
      listId: json['listId'],
      listName: json['listName'],
    );
  }
}
