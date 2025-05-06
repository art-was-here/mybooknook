import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'book_with_list.dart';

class ListManager {
  final BuildContext context;
  final Map<String, bool> _expandedLists = {};
  final Map<String, AnimationController> _animationControllers = {};
  final Map<String, Animation<double>> _listAnimations = {};
  final Map<String, String> _listNames = {};
  final Map<String, List<BookWithList>> _listBooks = {};
  bool _isInitialized = false;

  ListManager(this.context);

  Map<String, bool> get expandedLists => _expandedLists;
  Map<String, AnimationController> get animationControllers =>
      _animationControllers;
  Map<String, Animation<double>> get listAnimations => _listAnimations;
  Map<String, String> get listNames => _listNames;
  Map<String, List<BookWithList>> get listBooks => _listBooks;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Load all data from local storage first
    await loadExpandedStates();
    await loadListNames();
    await loadListBooks();

    // Then sync with Firebase if needed
    await _syncWithFirebase();

    _isInitialized = true;
  }

  Future<void> _syncWithFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Get lists from Firebase
      final listsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .get();

      // Update local storage with any new data from Firebase
      for (var doc in listsSnapshot.docs) {
        final listId = doc.id;
        final listName = doc.data()['name'] as String;

        // Update list name if it's new or different
        if (!_listNames.containsKey(listId) || _listNames[listId] != listName) {
          _listNames[listId] = listName;
          await saveListNames();
        }

        // Get books for this list from Firebase
        final booksSnapshot = await doc.reference.collection('books').get();
        final List<BookWithList> firebaseBooks = booksSnapshot.docs
            .map((bookDoc) => BookWithList.fromJson(bookDoc.data()))
            .toList();

        // Update local books if they're different
        if (!_listBooks.containsKey(listId) ||
            _listBooks[listId]!.length != firebaseBooks.length ||
            !_areBooksEqual(_listBooks[listId]!, firebaseBooks)) {
          _listBooks[listId] = firebaseBooks;
          await saveListBooks();
        }
      }
    } catch (e) {
      print('Error syncing with Firebase: $e');
    }
  }

  bool _areBooksEqual(
      List<BookWithList> localBooks, List<BookWithList> firebaseBooks) {
    if (localBooks.length != firebaseBooks.length) return false;

    for (int i = 0; i < localBooks.length; i++) {
      if (localBooks[i].book.isbn != firebaseBooks[i].book.isbn ||
          localBooks[i].book.isRead != firebaseBooks[i].book.isRead ||
          localBooks[i].book.userRating != firebaseBooks[i].book.userRating) {
        return false;
      }
    }
    return true;
  }

  Future<void> loadExpandedStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expandedStates = prefs.getString('expandedLists');
      if (expandedStates != null) {
        final Map<String, dynamic> states = json.decode(expandedStates);
        states.forEach((key, value) {
          _expandedLists[key] = value as bool;
        });
      }
    } catch (e) {
      print('Error loading expanded states: $e');
    }
  }

  Future<void> saveExpandedStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('expandedLists', json.encode(_expandedLists));
    } catch (e) {
      print('Error saving expanded states: $e');
    }
  }

  Future<void> loadListNames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listNamesJson = prefs.getString('listNames');
      if (listNamesJson != null) {
        final Map<String, dynamic> names = json.decode(listNamesJson);
        names.forEach((key, value) {
          _listNames[key] = value as String;
        });
      }
    } catch (e) {
      print('Error loading list names: $e');
    }
  }

  Future<void> saveListNames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('listNames', json.encode(_listNames));
    } catch (e) {
      print('Error saving list names: $e');
    }
  }

  Future<void> loadListBooks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listBooksJson = prefs.getString('listBooks');
      if (listBooksJson != null) {
        final Map<String, dynamic> books = json.decode(listBooksJson);
        books.forEach((listId, bookList) {
          _listBooks[listId] = (bookList as List)
              .map((book) => BookWithList.fromJson(book))
              .toList();
        });
      }
    } catch (e) {
      print('Error loading list books: $e');
    }
  }

  Future<void> saveListBooks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> booksToSave = {};
      _listBooks.forEach((listId, books) {
        booksToSave[listId] = books.map((book) => book.toJson()).toList();
      });
      await prefs.setString('listBooks', json.encode(booksToSave));
    } catch (e) {
      print('Error saving list books: $e');
    }
  }

  Future<void> updateListName(String listId, String name) async {
    _listNames[listId] = name;
    await saveListNames();

    // Sync with Firebase
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .doc(listId)
          .update({'name': name});
    }
  }

  Future<void> updateListBooks(String listId, List<BookWithList> books) async {
    _listBooks[listId] = books;
    await saveListBooks();

    // Sync with Firebase
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final batch = FirebaseFirestore.instance.batch();
      final listRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .doc(listId);

      // Delete existing books
      final existingBooks = await listRef.collection('books').get();
      for (var doc in existingBooks.docs) {
        batch.delete(doc.reference);
      }

      // Add new books
      for (var book in books) {
        batch.set(
          listRef.collection('books').doc(book.book.isbn),
          book.toJson(),
        );
      }

      await batch.commit();
    }
  }

  Future<void> clearListData() async {
    _listNames.clear();
    _listBooks.clear();
    _expandedLists.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('listNames');
    await prefs.remove('listBooks');
    await prefs.remove('expandedLists');
  }

  void toggleListExpanded(String listName, TickerProviderStateMixin vsync) {
    final isExpanded = _expandedLists[listName] ?? true;
    _expandedLists[listName] = !isExpanded;

    if (!_animationControllers.containsKey(listName)) {
      _animationControllers[listName] = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 300),
      );
      _listAnimations[listName] = CurvedAnimation(
        parent: _animationControllers[listName]!,
        curve: Curves.easeInOut,
      );

      if (isExpanded) {
        _animationControllers[listName]!.value = 1.0;
      }
    }

    if (isExpanded) {
      _animationControllers[listName]!.reverse();
    } else {
      _animationControllers[listName]!.forward();
    }

    saveExpandedStates();
  }

  Animation<double> getAnimationForList(
      String listName, TickerProviderStateMixin vsync) {
    if (!_animationControllers.containsKey(listName)) {
      _animationControllers[listName] = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 300),
      );
      _listAnimations[listName] = CurvedAnimation(
        parent: _animationControllers[listName]!,
        curve: Curves.easeInOut,
      );

      if (_expandedLists[listName] ?? true) {
        _animationControllers[listName]!.value = 1.0;
      }
    }

    return _listAnimations[listName]!;
  }

  void dispose() {
    for (var controller in _animationControllers.values) {
      controller.dispose();
    }
  }
}
