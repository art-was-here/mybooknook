import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/books/v1.dart';
import 'package:http/src/client.dart';
import '../models/book.dart';
import 'auth_client.dart';

class BookService {
  final BuildContext context;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/books'],
  );

  BookService(this.context);

  Future<BooksApi?> _getBooksApi() async {
    try {
      print('Attempting silent sign-in for Google Books API');
      var googleUser = await _googleSignIn.signInSilently();
      if (googleUser == null) {
        print('Silent sign-in failed, attempting interactive sign-in');
        googleUser = await _googleSignIn.signIn();
      }
      if (googleUser == null) {
        print('No Google user available');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to authenticate with Google Books API. Please try signing in again.'),
          ),
        );
        return null;
      }

      print('Sign-in successful: ${googleUser.email}');
      final authHeaders = await googleUser.authHeaders;
      print('Auth headers obtained');
      final client = AuthClient(authHeaders);
      return BooksApi(client as Client);
    } catch (e, stackTrace) {
      print('Error initializing Books API: $e');
      print('Stack trace: $stackTrace');
      String errorMessage = 'Error initializing Books API: $e';
      if (e.toString().contains('403') || e.toString().contains('access_denied')) {
        errorMessage =
            'Access blocked: myBookNook is not verified with Google. Contact the developer to add you as a tester or wait for verification.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      return null;
    }
  }

  Future<Book?> fetchBookDetails(String isbn) async {
    print('Fetching book details for ISBN: $isbn');
    final booksApi = await _getBooksApi();
    if (booksApi == null) {
      print('Books API unavailable');
      return null;
    }

    try {
      print('Querying Google Books API with isbn:$isbn');
      final response = await booksApi.volumes.list('isbn:$isbn');
      print('API response received: items=${response.items?.length ?? 0}');
      if (response.items != null && response.items!.isNotEmpty) {
        final bookData = response.items![0].volumeInfo!;
        print('Book data: title=${bookData.title}');
        return Book(
          title: bookData.title ?? 'Unknown Title',
          description: bookData.description ?? 'No description available',
          isbn: isbn,
          imageUrl: bookData.imageLinks?.thumbnail,
          averageRating: bookData.averageRating,
          authors: bookData.authors,
          categories: bookData.categories,
          publisher: bookData.publisher,
          publishedDate: bookData.publishedDate,
          pageCount: bookData.pageCount,
        );
      } else {
        print('No books found for ISBN: $isbn');
        return null;
      }
    } catch (e, stackTrace) {
      print('Error fetching book: $e');
      print('Stack trace: $stackTrace');
      String errorMessage = 'Error fetching book: $e';
      if (e.toString().contains('403') || e.toString().contains('access_denied')) {
        errorMessage =
            'Access blocked: myBookNook is not verified with Google. Contact the developer to add you as a tester or wait for verification.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      return null;
    }
  }

  Future<List<Book>> searchBooks(String query) async {
    if (query.trim().isEmpty) {
      print('Empty search query');
      return [];
    }
    final booksApi = await _getBooksApi();
    if (booksApi == null) {
      print('Books API unavailable');
      return [];
    }

    try {
      print('Searching Google Books API with query: $query');
      final response = await booksApi.volumes.list(
        query,
        orderBy: 'relevance',
        printType: 'books',
      );
      print('API response received: items=${response.items?.length ?? 0}');
      if (response.items == null || response.items!.isEmpty) {
        print('No books found for query: $query');
        return [];
      }
      return response.items!.map((item) {
        final bookData = item.volumeInfo!;
        String isbn = '';
        if (bookData.industryIdentifiers != null) {
          for (var id in bookData.industryIdentifiers!) {
            if (id.type == 'ISBN_13' || id.type == 'ISBN_10') {
              isbn = id.identifier ?? '';
              break;
            }
          }
        }
        return Book(
          title: bookData.title ?? 'Unknown Title',
          description: bookData.description ?? 'No description available',
          isbn: isbn,
          imageUrl: bookData.imageLinks?.thumbnail,
          averageRating: bookData.averageRating,
          authors: bookData.authors,
          categories: bookData.categories,
          publisher: bookData.publisher,
          publishedDate: bookData.publishedDate,
          pageCount: bookData.pageCount,
        );
      }).toList();
    } catch (e, stackTrace) {
      print('Error searching books: $e');
      print('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching books: $e')),
      );
      return [];
    }
  }

  Future<void> updateBookRating(String isbn, String bookTitle, int newRating, String selectedListName, String? selectedListId) async {
    print('Updating rating for book: $bookTitle, ISBN: $isbn, Rating: $newRating');
    final user = FirebaseAuth.instance.currentUser!;
    try {
      if (selectedListName == 'myBookNook') {
        print('Updating rating in myBookNook list');
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .where('name', isEqualTo: 'myBookNook')
            .limit(1)
            .get();
        if (snapshot.docs.isEmpty) {
          print('myBookNook list not found');
          throw Exception('myBookNook list not found');
        }
        final listId = snapshot.docs.first.id;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .doc(listId)
            .collection('books')
            .doc(isbn)
            .update({'userRating': newRating}).timeout(const Duration(seconds: 5), onTimeout: () {
          print('Rating update timed out');
          throw Exception('Rating update timed out');
        });
        print('Rating updated in myBookNook: $bookTitle, Rating: $newRating');
      } else {
        print('Updating rating in list: $selectedListName');
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .doc(selectedListId)
            .collection('books')
            .doc(isbn)
            .update({'userRating': newRating}).timeout(const Duration(seconds: 5), onTimeout: () {
          print('Rating update timed out');
          throw Exception('Rating update timed out');
        });
        print('Rating updated in $selectedListName: $bookTitle, Rating: $newRating');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rated $bookTitle: $newRating stars')),
      );
    } catch (e, stackTrace) {
      print('Error updating rating: $e');
      print('Stack trace: $stackTrace');
      String errorMessage = 'Error updating rating: $e';
      if (e.toString().contains('permission-denied')) {
        errorMessage = 'Permission denied updating rating. Please sign out and sign in again.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      throw Exception(errorMessage);
    }
  }

  Future<void> deleteBook(String isbn, String bookTitle, String selectedListName, String? selectedListId) async {
    print('Deleting book: $bookTitle, ISBN: $isbn');
    final user = FirebaseAuth.instance.currentUser!;
    try {
      if (selectedListName == 'myBookNook') {
        print('Deleting book from myBookNook list');
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .where('name', isEqualTo: 'myBookNook')
            .limit(1)
            .get();
        if (snapshot.docs.isEmpty) {
          print('myBookNook list not found');
          throw Exception('myBookNook list not found');
        }
        final listId = snapshot.docs.first.id;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .doc(listId)
            .collection('books')
            .doc(isbn)
            .delete()
            .timeout(const Duration(seconds: 5), onTimeout: () {
          print('Deletion timed out');
          throw Exception('Deletion timed out');
        });
        print('Book deleted from myBookNook: $bookTitle');
      } else {
        print('Deleting book from list: $selectedListName');
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .doc(selectedListId)
            .collection('books')
            .doc(isbn)
            .delete()
            .timeout(const Duration(seconds: 5), onTimeout: () {
          print('Deletion timed out');
          throw Exception('Deletion timed out');
        });
        print('Book deleted from $selectedListName: $bookTitle');
      }
    } catch (e, stackTrace) {
      print('Error deleting book: $e');
      print('Stack trace: $stackTrace');
      String errorMessage = 'Error deleting book: $e';
      if (e.toString().contains('permission-denied')) {
        errorMessage = 'Permission denied deleting book. Please sign out and sign in again.';
      }
      throw Exception(errorMessage);
    }
  }
}