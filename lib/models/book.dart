import 'package:shared_preferences/shared_preferences.dart';

class Book {
  final String title;
  final List<String>? authors;
  final String? description;
  final String? imageUrl;
  final String isbn;
  final String? publishedDate;
  final String? publisher;
  final int? pageCount;
  final List<String>? categories;
  final List<String>? tags;
  bool isRead;
  final int? currentPage;
  final DateTime? startedReading;
  final DateTime? finishedReading;
  final double? averageRating;
  final int? ratingsCount;
  final double? userRating;

  Book({
    required this.title,
    this.authors,
    this.description,
    this.imageUrl,
    required this.isbn,
    this.publishedDate,
    this.publisher,
    this.pageCount,
    this.categories,
    this.tags,
    this.isRead = false,
    this.currentPage,
    this.startedReading,
    this.finishedReading,
    this.averageRating,
    this.ratingsCount,
    this.userRating,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'authors': authors,
      'description': description,
      'imageUrl': imageUrl,
      'isbn': isbn,
      'publishedDate': publishedDate,
      'publisher': publisher,
      'pageCount': pageCount,
      'categories': categories,
      'tags': tags,
      'isRead': isRead,
      'currentPage': currentPage,
      'startedReading': startedReading?.toIso8601String(),
      'finishedReading': finishedReading?.toIso8601String(),
      'averageRating': averageRating,
      'ratingsCount': ratingsCount,
      'userRating': userRating,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      title: map['title']?.toString() ?? 'Unknown Title',
      authors: (map['authors'] as List<dynamic>?)?.cast<String>(),
      description: map['description']?.toString(),
      imageUrl: map['imageUrl']?.toString(),
      isbn: map['isbn']?.toString() ?? '',
      publishedDate: map['publishedDate']?.toString(),
      publisher: map['publisher']?.toString(),
      pageCount: map['pageCount'] as int?,
      categories: (map['categories'] as List<dynamic>?)?.cast<String>(),
      tags: (map['tags'] as List<dynamic>?)?.cast<String>(),
      isRead: map['isRead'] as bool? ?? false,
      currentPage: map['currentPage'] as int?,
      startedReading: map['startedReading'] != null
          ? DateTime.parse(map['startedReading'])
          : null,
      finishedReading: map['finishedReading'] != null
          ? DateTime.parse(map['finishedReading'])
          : null,
      averageRating: map['averageRating'] as double?,
      ratingsCount: map['ratingsCount'] as int?,
      userRating: map['userRating'] as double?,
    );
  }

  Book copyWith({
    String? title,
    List<String>? authors,
    String? description,
    String? imageUrl,
    String? isbn,
    String? publishedDate,
    String? publisher,
    int? pageCount,
    List<String>? categories,
    List<String>? tags,
    bool? isRead,
    int? currentPage,
    DateTime? startedReading,
    DateTime? finishedReading,
    double? averageRating,
    int? ratingsCount,
    double? userRating,
  }) {
    return Book(
      title: title ?? this.title,
      authors: authors ?? this.authors,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      isbn: isbn ?? this.isbn,
      publishedDate: publishedDate ?? this.publishedDate,
      publisher: publisher ?? this.publisher,
      pageCount: pageCount ?? this.pageCount,
      categories: categories ?? this.categories,
      tags: tags ?? this.tags,
      isRead: isRead ?? this.isRead,
      currentPage: currentPage ?? this.currentPage,
      startedReading: startedReading ?? this.startedReading,
      finishedReading: finishedReading ?? this.finishedReading,
      averageRating: averageRating ?? this.averageRating,
      ratingsCount: ratingsCount ?? this.ratingsCount,
      userRating: userRating ?? this.userRating,
    );
  }

  double get readingProgress {
    if (pageCount == null || currentPage == null) return 0.0;
    return (currentPage! / pageCount!) * 100;
  }

  static Future<bool> isBookCompleted(String isbn) async {
    final prefs = await SharedPreferences.getInstance();
    final completedBooks = prefs.getStringList('completed_books') ?? [];
    return completedBooks.contains(isbn);
  }
}
