import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

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
      title: map['title'],
      authors:
          map['authors'] != null ? List<String>.from(map['authors']) : null,
      description: map['description'],
      imageUrl: map['imageUrl'],
      isbn: map['isbn'],
      publishedDate: map['publishedDate'],
      publisher: map['publisher'],
      pageCount: map['pageCount'],
      categories: map['categories'] != null
          ? List<String>.from(map['categories'])
          : null,
      tags: map['tags'] != null ? List<String>.from(map['tags']) : null,
      isRead: map['isRead'] ?? false,
      currentPage: map['currentPage'],
      startedReading: map['startedReading'] != null
          ? DateTime.parse(map['startedReading'])
          : null,
      finishedReading: map['finishedReading'] != null
          ? DateTime.parse(map['finishedReading'])
          : null,
      averageRating: map['averageRating'],
      ratingsCount: map['ratingsCount'],
      userRating: map['userRating'],
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

  static Future<Book?> loadFromLocal(String isbn) async {
    final prefs = await SharedPreferences.getInstance();
    final bookJson = prefs.getString('book_$isbn');
    if (bookJson != null) {
      return Book.fromMap(json.decode(bookJson));
    }
    return null;
  }

  Future<void> saveToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('book_$isbn', json.encode(toMap()));
  }

  Future<void> saveToFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('books')
          .doc(isbn)
          .set(toMap());
    } catch (e) {
      print('Error saving book to Firebase: $e');
    }
  }

  static Future<Book?> loadFromFirebase(String isbn) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('books')
          .doc(isbn)
          .get();

      if (doc.exists) {
        return Book.fromMap(doc.data()!);
      }
    } catch (e) {
      print('Error loading book from Firebase: $e');
    }
    return null;
  }

  static Future<Book> load(String isbn) async {
    // Try local storage first
    Book? book = await loadFromLocal(isbn);

    // If not found locally, try Firebase
    if (book == null) {
      book = await loadFromFirebase(isbn);
      if (book != null) {
        // Save to local storage for future use
        await book.saveToLocal();
      }
    }

    return book ??
        Book(
          title: 'Unknown Title',
          isbn: isbn,
        );
  }

  Future<void> save() async {
    // Save to local storage first
    await saveToLocal();

    // Then sync with Firebase
    await saveToFirebase();
  }

  static Future<bool> isBookCompleted(String isbn) async {
    final prefs = await SharedPreferences.getInstance();
    final completedBooks = prefs.getStringList('completed_books') ?? [];
    return completedBooks.contains(isbn);
  }

  static Future<void> markBookCompleted(String isbn) async {
    final prefs = await SharedPreferences.getInstance();
    final completedBooks = prefs.getStringList('completed_books') ?? [];
    if (!completedBooks.contains(isbn)) {
      completedBooks.add(isbn);
      await prefs.setStringList('completed_books', completedBooks);
    }
  }

  static Future<void> markBookUncompleted(String isbn) async {
    final prefs = await SharedPreferences.getInstance();
    final completedBooks = prefs.getStringList('completed_books') ?? [];
    completedBooks.remove(isbn);
    await prefs.setStringList('completed_books', completedBooks);
  }
}
