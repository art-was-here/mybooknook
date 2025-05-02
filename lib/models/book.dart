class Book {
  final String title;
  final String description;
  final String isbn;
  final String? imageUrl;
  final double? averageRating;
  final int? ratingsCount;
  final List<String>? authors;
  final List<String>? categories;
  final String? publisher;
  final String? publishedDate;
  final int? pageCount;
  final int userRating;
  final DateTime? dateAdded;
  final DateTime? releaseDate;
  final List<String>? tags; // Add tags field

  Book({
    required this.title,
    required this.description,
    required this.isbn,
    this.imageUrl,
    this.averageRating,
    this.ratingsCount,
    this.authors,
    this.categories,
    this.publisher,
    this.publishedDate,
    this.pageCount,
    this.userRating = 0,
    this.dateAdded,
    this.releaseDate,
    this.tags,
  });

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      title: map['title'] ?? 'Unknown Title',
      description: map['description'] ?? 'No description available',
      isbn: map['isbn'] ?? '',
      imageUrl: map['imageUrl'],
      averageRating: map['averageRating']?.toDouble(),
      ratingsCount: map['ratingsCount'],
      authors:
          map['authors'] != null ? List<String>.from(map['authors']) : null,
      categories: map['categories'] != null
          ? List<String>.from(map['categories'])
          : null,
      publisher: map['publisher'],
      publishedDate: map['publishedDate'],
      pageCount: map['pageCount'],
      userRating: map['userRating'] ?? 0,
      dateAdded: map['createdAt']?.toDate(),
      releaseDate: map['publishedDate'] != null
          ? DateTime.tryParse(map['publishedDate'])
          : null,
      tags: map['tags'] != null ? List<String>.from(map['tags']) : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'isbn': isbn,
      'imageUrl': imageUrl,
      'averageRating': averageRating,
      'ratingsCount': ratingsCount,
      'authors': authors,
      'categories': categories,
      'publisher': publisher,
      'publishedDate': publishedDate,
      'pageCount': pageCount,
      'userRating': userRating,
      'createdAt': dateAdded ?? DateTime.now(),
      'tags': tags,
    };
  }
}
