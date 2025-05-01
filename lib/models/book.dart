class Book {
  final String title;
  final String description;
  final String isbn;
  final String? imageUrl;
  final double? averageRating;
  final List<String>? authors;
  final List<String>? categories;
  final String? publisher;
  final String? publishedDate;
  final int? pageCount;
  final int userRating; // 0-5, 0 means unrated

  Book({
    required this.title,
    required this.description,
    required this.isbn,
    this.imageUrl,
    this.averageRating,
    this.authors,
    this.categories,
    this.publisher,
    this.publishedDate,
    this.pageCount,
    this.userRating = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'isbn': isbn,
      'imageUrl': imageUrl,
      'averageRating': averageRating,
      'authors': authors,
      'categories': categories,
      'publisher': publisher,
      'publishedDate': publishedDate,
      'pageCount': pageCount,
      'userRating': userRating,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      title: map['title'] ?? 'Unknown Title',
      description: map['description'] ?? 'No description available',
      isbn: map['isbn'] ?? '',
      imageUrl: map['imageUrl'],
      averageRating: map['averageRating']?.toDouble(),
      authors: map['authors'] != null ? List<String>.from(map['authors']) : null,
      categories: map['categories'] != null ? List<String>.from(map['categories']) : null,
      publisher: map['publisher'],
      publishedDate: map['publishedDate'],
      pageCount: map['pageCount'],
      userRating: map['userRating'] ?? 0,
    );
  }
}