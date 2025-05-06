import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import '../models/book.dart';
import '../models/settings.dart' as app_settings;
import '../services/book_service.dart';
import '../services/barcode_service.dart';
import '../services/text_recognition_service.dart';
import '../services/database_service.dart';
import '../services/book_cache_service.dart';
import '../services/firestore_service.dart';
import '../services/book_loading_service.dart';
import '../services/book_sorting_service.dart';
import '../services/error_service.dart';
import 'book_search_sheet.dart';
import 'book_details_card.dart';
import 'profile_image_widget.dart';
import 'scan_book_details_card.dart';
import 'home_screen/list_item.dart';
import 'home_screen/list_manager.dart';
import 'home_screen/book_with_list.dart';
import '../screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final Color accentColor;
  final Function(Color) onAccentColorChanged;

  const HomeScreen({
    super.key,
    required this.onThemeChanged,
    required this.accentColor,
    required this.onAccentColorChanged,
  });

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  String? _selectedListId;
  String _selectedListName = 'Home';
  final _fabKey = GlobalKey<ExpandableFabState>();
  String? _errorMessage;
  bool _isLoading = true;
  BookService? _bookService;
  StreamSubscription<User?>? _authSubscription;
  String _sortPreference = 'title';
  Map<String, String> _listNamesCache = {};
  DateTime? _listNamesLastUpdated;
  List<BookWithList> _loadedBooks = [];
  Database? _database;
  bool _isOffline = false;
  final Map<String, Book> _bookCache = {};
  final Map<String, DateTime> _bookCacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(hours: 1);
  ListManager? _listManager;
  late BuildContext _buildContext;
  DateTime? _lastBackPressTime;
  String? _cachedProfileImage;
  bool _isProfileImageLoading = true;

  // Services
  late final DatabaseService _databaseService;
  late final BookCacheService _bookCacheService;
  late final BookLoadingService _bookLoadingService;
  late final BookSortingService _bookSortingService;

  @override
  void initState() {
    super.initState();
    print('HomeScreen initState called');

    // Initialize services first
    _initializeFirestore();
    _initializeDatabase();
    _ensureIndexes();
    _loadCachedProfileImage();

    // Check authentication state immediately
    final currentUser = FirebaseAuth.instance.currentUser;
    print('Current user: ${currentUser?.uid ?? "No user"}');

    if (currentUser != null) {
      print('User already authenticated, initializing...');
      _initializeDefaultList().then((_) {
        print('Default list initialized, loading books...');
        _loadBooks();
      });
    } else {
      print('No authenticated user, waiting for auth state changes...');
    }

    // Listen for auth state changes
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      print('Auth state changed: ${user?.uid ?? "No user"}');
      if (user != null && mounted) {
        print('New user authenticated, initializing...');
        _initializeDefaultList().then((_) {
          print('Default list initialized, loading books...');
          _loadBooks();
        });
      }
    }, onError: (e, stackTrace) {
      print('Error in auth state listener: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ErrorService.setError(
            'Authentication error: $e. Please sign in again.');
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _initializeFirestore() async {
    try {
      await FirebaseFirestore.instance.enablePersistence();
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    } catch (e) {
      print('Error enabling Firestore persistence: $e');
    }
  }

  Future<void> _initializeDatabase() async {
    try {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'mybooknook.db');

      _database = await openDatabase(
        path,
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE books(
              id TEXT PRIMARY KEY,
              title TEXT,
              authors TEXT,
              description TEXT,
              imageUrl TEXT,
              isbn TEXT,
              publishedDate TEXT,
              publisher TEXT,
              pageCount INTEGER,
              categories TEXT,
              tags TEXT,
              listId TEXT,
              listName TEXT,
              userId TEXT,
              createdAt TEXT,
              lastUpdated TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE lists(
              id TEXT PRIMARY KEY,
              name TEXT,
              createdAt TEXT,
              lastUpdated TEXT
            )
          ''');
        },
      );
    } catch (e) {
      print('Error initializing database: $e');
    }
  }

  Future<void> _cacheBook(Book book, String listId, String listName) async {
    if (_database == null) return;

    try {
      final now = DateTime.now();
      final bookData = {
        'id': book.isbn,
        'title': book.title,
        'authors': book.authors?.join(','),
        'description': book.description ?? '',
        'imageUrl': book.imageUrl,
        'isbn': book.isbn,
        'publishedDate': book.publishedDate,
        'publisher': book.publisher,
        'pageCount': book.pageCount,
        'categories': book.categories?.join(','),
        'tags': book.tags?.join(','),
        'listId': listId,
        'listName': listName,
        'userId': FirebaseAuth.instance.currentUser?.uid,
        'createdAt': now.toIso8601String(),
        'lastUpdated': now.toIso8601String(),
      };

      // Update in-memory cache
      _bookCache[book.isbn] = book;
      _bookCacheTimestamps[book.isbn] = now;

      // Update SQLite cache
      await _database!.insert(
        'books',
        bookData,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print('Error caching book: $e');
    }
  }

  Future<Book?> _getCachedBook(String isbn) async {
    // Check in-memory cache first
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

    // Check SQLite cache
    if (_database != null) {
      try {
        final List<Map<String, dynamic>> maps = await _database!.query(
          'books',
          where: 'isbn = ?',
          whereArgs: [isbn],
        );

        if (maps.isNotEmpty) {
          final data = maps.first;
          final book = Book(
            title: data['title'] as String,
            authors: (data['authors'] as String?)?.split(','),
            description: data['description'] as String? ?? '',
            imageUrl: data['imageUrl'] as String?,
            isbn: data['isbn'] as String,
            publishedDate: data['publishedDate'] as String?,
            publisher: data['publisher'] as String?,
            pageCount: data['pageCount'] as int?,
            categories: (data['categories'] as String?)?.split(','),
            tags: (data['tags'] as String?)?.split(','),
          );

          // Update in-memory cache
          _bookCache[isbn] = book;
          _bookCacheTimestamps[isbn] = DateTime.now();

          return book;
        }
      } catch (e) {
        print('Error getting cached book: $e');
      }
    }

    return null;
  }

  Future<void> _cacheList(String listId, String listName) async {
    if (_database == null) return;

    try {
      final now = DateTime.now();
      await _database!.insert(
        'lists',
        {
          'id': listId,
          'name': listName,
          'createdAt': now.toIso8601String(),
          'lastUpdated': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      print('Error caching list: $e');
    }
  }

  Future<List<BookWithList>> _getCachedBooks(String listId) async {
    if (_database == null) return [];

    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        'books',
        where: listId == 'Home' ? null : 'listId = ?',
        whereArgs: listId == 'Home' ? null : [listId],
      );

      return maps.map((map) {
        final book = Book(
          title: map['title'] as String,
          authors: (map['authors'] as String?)?.split(','),
          description: map['description'] as String? ?? '',
          imageUrl: map['imageUrl'] as String?,
          isbn: map['isbn'] as String,
          publishedDate: map['publishedDate'] as String?,
          publisher: map['publisher'] as String?,
          pageCount: map['pageCount'] as int?,
          categories: (map['categories'] as String?)?.split(','),
          tags: (map['tags'] as String?)?.split(','),
        );

        return BookWithList(
          book: book,
          listId: map['listId'] as String,
          listName: map['listName'] as String,
        );
      }).toList();
    } catch (e) {
      print('Error getting cached books: $e');
      return [];
    }
  }

  Future<Map<String, String>> _getCachedLists() async {
    if (_database == null) return {};

    try {
      final List<Map<String, dynamic>> maps = await _database!.query('lists');
      return {for (var map in maps) map['id']: map['name']};
    } catch (e) {
      print('Error getting cached lists: $e');
      return {};
    }
  }

  Future<void> _migrateBooks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    print('Starting book migration for user: ${user.uid}');
    try {
      final listsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .get();

      for (var listDoc in listsSnapshot.docs) {
        final booksSnapshot = await listDoc.reference.collection('books').get();
        final batch = FirebaseFirestore.instance.batch();
        int batchCount = 0;

        for (var bookDoc in booksSnapshot.docs) {
          final data = bookDoc.data();
          bool needsUpdate = false;
          Map<String, dynamic> updates = {};

          if (data['userId'] != user.uid) {
            updates['userId'] = user.uid;
            needsUpdate = true;
          }
          if (data['tags'] == null) {
            updates['tags'] = data['categories'] != null
                ? List<String>.from(data['categories'])
                : [];
            needsUpdate = true;
          }

          if (needsUpdate) {
            batch.update(bookDoc.reference, updates);
            batchCount++;

            // Firestore has a limit of 500 operations per batch
            if (batchCount >= 500) {
              await batch.commit();
              batchCount = 0;
            }
          }
        }

        // Commit any remaining operations
        if (batchCount > 0) {
          await batch.commit();
        }
      }
      print('Book migration completed');
    } catch (e, stackTrace) {
      print('Error during migration: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<void> _cleanupStrayBooks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    print('Starting cleanup of stray books for user: ${user.uid}');
    try {
      final booksSnapshot =
          await FirebaseFirestore.instance.collectionGroup('books').get();
      final batch = FirebaseFirestore.instance.batch();
      int batchCount = 0;

      for (var bookDoc in booksSnapshot.docs) {
        final path = bookDoc.reference.path;
        if (!path.contains('/users/${user.uid}/lists/')) {
          print('Found stray book at path: $path');
          batch.delete(bookDoc.reference);
          batchCount++;

          // Firestore has a limit of 500 operations per batch
          if (batchCount >= 500) {
            await batch.commit();
            batchCount = 0;
          }
        }
      }

      // Commit any remaining operations
      if (batchCount > 0) {
        await batch.commit();
      }
      print('Stray books cleanup completed');
    } catch (e, stackTrace) {
      print('Error during stray books cleanup: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _sortPreference = prefs.getString('sortPreference') ?? 'title';
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _listManager?.dispose();
    print('HomeScreen dispose: Canceled auth subscription and list manager');
    super.dispose();
  }

  Future<void> _initializeDefaultList() async {
    if (!mounted) return;
    print('Initializing default list');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('No authenticated user found');
      if (mounted) {
        setState(() {
          _errorMessage = 'No authenticated user. Please sign in again.';
          _isLoading = false;
        });
      }
      return;
    }

    print('Authenticated user: UID=${user.uid}, email=${user.email}');

    try {
      print('Creating/updating user document');
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));

      print('Checking for Home list');
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .where('name', isEqualTo: 'Home')
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        print('Creating new Home list');
        final listRef = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .add({
          'name': 'Home',
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('Created Home list with ID: ${listRef.id}');
        if (mounted) {
          setState(() {
            _selectedListId = listRef.id;
            _selectedListName = 'Home';
            _isLoading = false;
          });
        }
      } else {
        print('Found existing Home list with ID: ${snapshot.docs.first.id}');
        if (mounted) {
          setState(() {
            _selectedListId = snapshot.docs.first.id;
            _selectedListName = 'Home';
            _isLoading = false;
          });
        }
      }
    } catch (e, stackTrace) {
      print('Error initializing default list: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to initialize: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addNewList(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('New List'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter list name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final listRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('lists')
              .doc();

          await listRef.set({
            'name': result,
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Update the list names cache
          _listNamesCache[listRef.id] = result;
          _listNamesLastUpdated = DateTime.now();

          // Refresh the UI
          if (mounted) {
            setState(() {
              _selectedListId = listRef.id;
              _selectedListName = result;
            });
            await _loadBooks();
          }

          ScaffoldMessenger.of(_buildContext).showSnackBar(
            SnackBar(content: Text('Created new list: $result')),
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(_buildContext).showSnackBar(
              SnackBar(content: Text('Error creating list: $e')),
            );
          }
        }
      }
    }
  }

  Future<void> _deleteList(BuildContext context, String listId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Delete List'),
        content: const Text(
            'Are you sure you want to delete this list and all its books?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          // First, get all books in the list
          final booksSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('lists')
              .doc(listId)
              .collection('books')
              .get();

          // Create a batch operation
          final batch = FirebaseFirestore.instance.batch();

          // Add all books to the batch for deletion
          for (var doc in booksSnapshot.docs) {
            batch.delete(doc.reference);
          }

          // Add the list document to the batch for deletion
          final listRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('lists')
              .doc(listId);
          batch.delete(listRef);

          // Commit the batch operation
          await batch.commit();

          // Clear all caches
          _clearListNamesCache();
          _bookCache.clear();
          _bookCacheTimestamps.clear();

          // Update the UI
          if (mounted) {
            // Remove books from the deleted list
            _loadedBooks.removeWhere((book) => book.listId == listId);

            // If we're currently viewing the deleted list, switch to Home
            if (_selectedListId == listId) {
              _selectedListId = null;
              _selectedListName = 'Home';
            }
          }

          // Reload the current view
          if (_selectedListId == null) {
            await _initializeDefaultList();
          }
          await _loadBooks();

          ScaffoldMessenger.of(_buildContext).showSnackBar(
            const SnackBar(
                content: Text('List and all its books deleted successfully')),
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(_buildContext).showSnackBar(
              SnackBar(content: Text('Error deleting list: $e')),
            );
          }
        }
      }
    }
  }

  Future<void> _showAddToListDialog(BuildContext context, Book book) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final listsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .get();

      final lists = listsSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'name': data['name'] as String? ?? 'Unknown List',
        };
      }).toList();

      if (!mounted) return;

      final selectedList = await showDialog<Map<String, String>>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Add to List'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: lists.length,
              itemBuilder: (context, index) {
                final list = lists[index];
                return ListTile(
                  title: Text(list['name']!),
                  onTap: () => Navigator.pop(dialogContext, list),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selectedList != null) {
        try {
          // Add the book to Firestore
          final bookRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('lists')
              .doc(selectedList['id'])
              .collection('books')
              .doc(); // Let Firestore generate a unique ID

          await bookRef.set({
            'title': book.title,
            'authors': book.authors,
            'description': book.description,
            'imageUrl': book.imageUrl,
            'isbn': book.isbn,
            'publishedDate': book.publishedDate,
            'publisher': book.publisher,
            'pageCount': book.pageCount,
            'categories': book.categories,
            'tags': book.tags,
            'userId': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Update the list names cache
          _listNamesCache[selectedList['id']!] = selectedList['name']!;
          _listNamesLastUpdated = DateTime.now();

          if (!mounted) return;
          ScaffoldMessenger.of(_buildContext).showSnackBar(
            SnackBar(content: Text('Added to ${selectedList['name']}')),
          );

          // Update the UI
          if (mounted) {
            // If we're in Home view or the list we just added to, update the UI
            if (_selectedListName == 'Home' ||
                _selectedListId == selectedList['id']) {
              // Create a new BookWithList object for the added book
              final newBookWithList = BookWithList(
                book: book,
                listId: selectedList['id']!,
                listName: selectedList['name']!,
              );

              // Update the state
              setState(() {
                // Clear the current books list
                _loadedBooks.clear();

                // Add the new book
                _loadedBooks.add(newBookWithList);

                // If we're in Home view, we need to reload all books
                if (_selectedListName == 'Home') {
                  _loadBooks();
                } else {
                  // For a specific list, just sort the current books
                  _sortBooks();
                }
              });
            }
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(_buildContext).showSnackBar(
            SnackBar(content: Text('Error adding book: $e')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(_buildContext).showSnackBar(
        SnackBar(content: Text('Error loading lists: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _buildContext = context;
    // Initialize services with the current context if they haven't been initialized yet
    _bookService ??= BookService(context);
    _listManager ??= ListManager(context);
    _listManager?.loadExpandedStates();

    final user = FirebaseAuth.instance.currentUser;
    print(
        'Building HomeScreen for user: ${user?.email ?? "No user"}, UID: ${user?.uid ?? "No UID"}');
    print(
        'Selected List: $_selectedListName, ID: $_selectedListId, Sort: $_sortPreference');
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'add_list' && mounted) {
                print('Add new list selected');
                await _addNewList(context);
              }
            },
            itemBuilder: (BuildContext popupContext) => [
              PopupMenuItem<String>(
                value: 'add_list',
                child: Row(
                  children: const [
                    Icon(Icons.add),
                    SizedBox(width: 8),
                    Text('Add New List'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              ..._buildListMenuItems(context),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_selectedListName),
                const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            offset: const Offset(0, 40),
            constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width,
              maxWidth: MediaQuery.of(context).size.width,
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: _isProfileImageLoading
                  ? const CircleAvatar(
                      radius: 18,
                      child: CircularProgressIndicator(),
                    )
                  : CircleAvatar(
                      radius: 18,
                      backgroundImage: _cachedProfileImage != null
                          ? MemoryImage(base64Decode(_cachedProfileImage!))
                              as ImageProvider
                          : null,
                      child: _cachedProfileImage == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
              onSelected: (String value) {
                if (value == 'profile') {
                  Navigator.pushNamed(context, '/profile');
                } else if (value == 'settings') {
                  Navigator.pushNamed(context, '/settings');
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person),
                      SizedBox(width: 8),
                      Text('Go to Profile'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings),
                      SizedBox(width: 8),
                      Text('Settings'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_errorMessage!),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            if (mounted) {
                              _initializeDefaultList();
                            }
                          },
                          child: const Text('Retry'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () async {
                            if (mounted) {
                              print('Signing out due to error');
                              await FirebaseAuth.instance.signOut();
                              await FirebaseAuth.instance
                                  .setPersistence(Persistence.NONE);
                              print('Signed out and cleared persistence');
                            }
                          },
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  )
                : _selectedListId == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                                'Failed to load list. Please try again.'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                if (mounted) {
                                  _initializeDefaultList();
                                }
                              },
                              child: const Text('Retry'),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () async {
                                if (mounted) {
                                  print('Signing out due to null list ID');
                                  await FirebaseAuth.instance.signOut();
                                  await FirebaseAuth.instance
                                      .setPersistence(Persistence.NONE);
                                  print('Signed out and cleared persistence');
                                }
                              },
                              child: const Text('Sign Out'),
                            ),
                          ],
                        ),
                      )
                    : StreamBuilder<QuerySnapshot>(
                        stream: _selectedListName == 'Home'
                            ? FirebaseFirestore.instance
                                .collectionGroup('books')
                                .where('userId', isEqualTo: user!.uid)
                                .orderBy('createdAt', descending: true)
                                .snapshots()
                            : FirebaseFirestore.instance
                                .collection('users')
                                .doc(user!.uid)
                                .collection('lists')
                                .doc(_selectedListId)
                                .collection('books')
                                .orderBy('createdAt', descending: true)
                                .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Text('Error: ${snapshot.error}'),
                            );
                          }

                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          final books = snapshot.data?.docs ?? [];
                          if (books.isEmpty) {
                            return const Center(child: Text('No books found'));
                          }

                          final groupedBooks = <String, List<BookWithList>>{};
                          for (var doc in books) {
                            final data = doc.data() as Map<String, dynamic>;
                            final book = Book(
                              title:
                                  data['title']?.toString() ?? 'Unknown Title',
                              authors: (data['authors'] as List<dynamic>?)
                                      ?.cast<String>() ??
                                  [],
                              description:
                                  data['description']?.toString() ?? '',
                              imageUrl: data['imageUrl']?.toString(),
                              isbn: data['isbn']?.toString() ?? '',
                              publishedDate: data['publishedDate']?.toString(),
                              publisher: data['publisher']?.toString(),
                              pageCount: data['pageCount'] as int?,
                              categories: (data['categories'] as List<dynamic>?)
                                      ?.cast<String>() ??
                                  [],
                              tags: (data['tags'] as List<dynamic>?)
                                      ?.cast<String>() ??
                                  [],
                            );

                            String listName = 'Unknown List';
                            String listId = '';

                            if (_selectedListName == 'Home') {
                              final path = doc.reference.path;
                              final parts = path.split('/');
                              if (parts.length >= 4) {
                                listId = parts[3];
                                listName =
                                    _listNamesCache[listId] ?? 'Unknown List';
                              }
                            } else {
                              listId = _selectedListId!;
                              listName = _selectedListName;
                            }

                            print('Processing book: ${book.title}');
                            print(
                                'Book ${book.title} belongs to list: $listName (ID: $listId)');
                            print('Book data: $data');

                            groupedBooks
                                .putIfAbsent(listName, () => [])
                                .add(BookWithList(
                                  book: book,
                                  listId: listId,
                                  listName: listName,
                                ));
                          }

                          final sortedListNames = groupedBooks.keys.toList()
                            ..sort();
                          final displayItems = <dynamic>[];
                          for (var listName in sortedListNames) {
                            displayItems.add(listName);
                            if (_listManager?.expandedLists[listName] ?? true) {
                              displayItems.addAll(groupedBooks[listName]!);
                            }
                          }

                          return ListView.builder(
                            itemCount: displayItems.length,
                            itemBuilder: (BuildContext listContext, int index) {
                              final item = displayItems[index];
                              if (item is String) {
                                final listName = item;
                                final bookCount =
                                    groupedBooks[listName]?.length ?? 0;
                                final isExpanded =
                                    _listManager?.expandedLists[listName] ??
                                        true;
                                final animation = _listManager
                                        ?.getAnimationForList(listName, this) ??
                                    AlwaysStoppedAnimation(1.0);

                                return ListItem(
                                  listName: listName,
                                  bookCount: bookCount,
                                  books: groupedBooks[listName],
                                  isExpanded: isExpanded,
                                  animation: animation,
                                  accentColor: widget.accentColor,
                                  onToggleExpanded: (name) => _listManager
                                      ?.toggleListExpanded(name, this),
                                  onBookTap: _onBookTap,
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          );
                        },
                      ),
        floatingActionButtonLocation: ExpandableFab.location,
        floatingActionButton: ExpandableFab(
          key: _fabKey,
          type: ExpandableFabType.up,
          distance: 60.0,
          children: [
            FloatingActionButton.small(
              heroTag: 'search_fab',
              backgroundColor: widget.accentColor.withOpacity(0.8),
              foregroundColor: Colors.white,
              onPressed: () {
                print('Search FAB pressed');
                final state = _fabKey.currentState;
                if (state != null && state.isOpen) {
                  print('Toggling FAB closed');
                  state.toggle();
                }
                BookSearchSheet.show(
                    context, _selectedListId, _selectedListName, _bookService!);
              },
              child: const Icon(Icons.search),
              tooltip: 'Search by Title or ISBN',
            ),
            FloatingActionButton.small(
              heroTag: 'scan_fab',
              backgroundColor: widget.accentColor.withOpacity(0.8),
              foregroundColor: Colors.white,
              onPressed: () {
                print('Scan FAB pressed');
                final state = _fabKey.currentState;
                if (state != null && state.isOpen) {
                  print('Toggling FAB closed');
                  state.toggle();
                }
                scanBarcode();
              },
              child: const Icon(Icons.camera_alt),
              tooltip: 'Scan ISBN',
            ),
          ],
          openButtonBuilder: RotateFloatingActionButtonBuilder(
            child: const Icon(Icons.add),
            foregroundColor: Colors.white,
            backgroundColor: widget.accentColor,
            shape: const CircleBorder(),
          ),
          closeButtonBuilder: DefaultFloatingActionButtonBuilder(
            child: const Icon(Icons.close),
            foregroundColor: Colors.white,
            backgroundColor: widget.accentColor,
            shape: const CircleBorder(),
          ),
        ),
      ),
    );
  }

  Future<Map<String, String>> _fetchListNames(String userId) async {
    if (!mounted) return {};

    // Return cached data if it's less than 5 minutes old
    if (_listNamesCache.isNotEmpty &&
        _listNamesLastUpdated != null &&
        DateTime.now().difference(_listNamesLastUpdated!) <
            const Duration(minutes: 5)) {
      print('Returning cached list names');
      return _listNamesCache;
    }

    print('Fetching list names for user: $userId');
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('lists')
          .get();
      print('List names query completed: ${snapshot.docs.length} lists found');
      _listNamesCache.clear();
      for (var doc in snapshot.docs) {
        final listName = doc['name'] as String;
        _listNamesCache[doc.id] = listName;
        print('Found list: $listName (ID: ${doc.id})');
      }
      _listNamesLastUpdated = DateTime.now();
      return _listNamesCache;
    } catch (e, stackTrace) {
      print('Error fetching list names: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Failed to fetch list names: $e');
    }
  }

  // Update the cache when lists are modified
  Future<void> _updateListNamesCache(String listId, String listName) async {
    _listNamesCache[listId] = listName;
    _listNamesLastUpdated = DateTime.now();
  }

  // Clear cache when needed
  void _clearListNamesCache() {
    _listNamesCache.clear();
    _listNamesLastUpdated = null;
  }

  // Add composite indexes for Firestore queries
  Future<void> _ensureIndexes() async {
    try {
      // Index for Home view books query
      await FirebaseFirestore.instance.collection('users').doc('_indexes').set({
        'indexes': {
          'books_home': {
            'fields': [
              {'fieldPath': 'userId', 'order': 'ASCENDING'},
              {'fieldPath': 'createdAt', 'order': 'DESCENDING'},
            ],
            'queryScope': 'COLLECTION_GROUP',
          },
          'books_list': {
            'fields': [
              {'fieldPath': 'createdAt', 'order': 'DESCENDING'},
            ],
            'queryScope': 'COLLECTION',
          },
        },
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error creating indexes: $e');
    }
  }

  void _sortBooks() {
    _loadedBooks.sort((a, b) => a.book.title.compareTo(b.book.title));
  }

  Future<void> _loadBooks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    print('Starting to load books');
    print('Loading books for user: ${user.uid}, list: $_selectedListId');

    try {
      // First, ensure we have the list names cache populated
      if (_selectedListName == 'Home') {
        await _fetchListNames(user.uid);
      }

      Query query;
      if (_selectedListName == 'Home') {
        print('Executing Firestore query for Home');
        // For Home view, get all books from all lists
        query = FirebaseFirestore.instance
            .collectionGroup('books')
            .where('userId', isEqualTo: user.uid)
            .orderBy('createdAt', descending: true);
      } else {
        print('Executing Firestore query for list $_selectedListId');
        // For specific list, get only books from that list
        query = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .doc(_selectedListId)
            .collection('books')
            .orderBy('createdAt', descending: true);
      }

      final querySnapshot = await query.get();
      print('Query completed: ${querySnapshot.docs.length} documents found');

      // Update total books count
      final settings = app_settings.Settings();
      await settings.load();
      await settings.updateBookCounts(
          querySnapshot.docs.length, settings.readBooks);
      await settings.save();

      // Clear the current books list
      _loadedBooks.clear();

      // Process each book
      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final book = Book(
          title: data['title']?.toString() ?? 'Unknown Title',
          authors: (data['authors'] as List<dynamic>?)?.cast<String>() ?? [],
          description: data['description']?.toString() ?? '',
          imageUrl: data['imageUrl']?.toString(),
          isbn: data['isbn']?.toString() ?? '',
          publishedDate: data['publishedDate']?.toString(),
          publisher: data['publisher']?.toString(),
          pageCount: data['pageCount'] as int?,
          categories:
              (data['categories'] as List<dynamic>?)?.cast<String>() ?? [],
          tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? [],
        );

        // Get the list name for this book
        String listName = 'Unknown List';
        String listId = '';

        if (_selectedListName == 'Home') {
          // For Home view, get the list name from the path
          final path = doc.reference.path;
          final parts = path.split('/');
          if (parts.length >= 4) {
            listId = parts[3];
            listName = _listNamesCache[listId] ?? 'Unknown List';
          }
        } else {
          // For specific list, use the current list name
          listId = _selectedListId!;
          listName = _selectedListName;
        }

        print('Processing book: ${book.title}');
        print('Book ${book.title} belongs to list: $listName (ID: $listId)');

        _loadedBooks.add(BookWithList(
          book: book,
          listId: listId,
          listName: listName,
        ));
      }

      // Sort books based on current sort order
      _sortBooks();

      print('Successfully processed ${_loadedBooks.length} books');

      // Force a UI update
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading books: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading books: $e';
        });
        ScaffoldMessenger.of(_buildContext).showSnackBar(
          SnackBar(content: Text('Error loading books: $e')),
        );
      }
    }
  }

  List<PopupMenuEntry<String>> _buildListMenuItems(BuildContext context) {
    return [
      PopupMenuItem<String>(
        value: 'home',
        onTap: () async {
          if (mounted) {
            setState(() {
              _selectedListId = null;
              _selectedListName = 'Home';
            });
            // First ensure we have the Home list initialized
            await _initializeDefaultList();
            // Then load the books
            await _loadBooks();
          }
        },
        child: const ListTile(
          title: Text('Home'),
        ),
      ),
      const PopupMenuDivider(),
      PopupMenuItem<String>(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseAuth.instance.currentUser != null
              ? FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .collection('lists')
                  .where('name', isNotEqualTo: 'Home')
                  .orderBy('name')
                  .orderBy('createdAt')
                  .snapshots()
              : Stream.empty(),
          builder: (BuildContext streamContext,
              AsyncSnapshot<QuerySnapshot> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ListTile(
                title: Text('Loading lists...'),
              );
            }

            if (snapshot.hasError) {
              return ListTile(
                title: Text('Error: ${snapshot.error}'),
              );
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const ListTile(
                title: Text('No lists found'),
              );
            }

            return Column(
              children: snapshot.data!.docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final listId = doc.id;
                final listName = data['name'] as String? ?? 'Unknown List';
                return PopupMenuItem<String>(
                  value: listId,
                  onTap: () async {
                    if (mounted) {
                      setState(() {
                        _selectedListId = listId;
                        _selectedListName = listName;
                      });
                      await _loadBooks();
                    }
                  },
                  child: ListTile(
                    title: Text(listName),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        _deleteList(_buildContext, listId);
                      },
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ),
    ];
  }

  Future<void> scanBarcode() async {
    if (!mounted) return;

    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final isbn = await TextRecognitionService.scanISBN();

      if (isbn == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'No ISBN found in the image. Please try again.';
          _isLoading = false;
        });
        return;
      }

      // Check cache first
      final cachedBook = await _getCachedBook(isbn);
      if (cachedBook != null) {
        if (!mounted) return;
        _showBookDetails(cachedBook, isScanned: true);
        return;
      }

      // Fetch book details from Google Books API
      final book = await _bookService!.fetchBookDetails(isbn);
      if (book == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'Book not found. Please try again.';
          _isLoading = false;
        });
        return;
      }

      // Cache the book
      await _cacheBook(book, _selectedListId ?? '', _selectedListName);

      // Show book details
      if (!mounted) return;
      _showBookDetails(book, isScanned: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error scanning book: $e';
        _isLoading = false;
      });
      ScaffoldMessenger.of(_buildContext).showSnackBar(
        SnackBar(content: Text('Error scanning book: $e')),
      );
    }
  }

  void _showBookDetails(Book book, {bool isScanned = false}) {
    if (!mounted) return;

    // Find the book in _loadedBooks to get its actual list ID
    final bookWithList = _loadedBooks.firstWhere(
      (b) => b.book.isbn == book.isbn,
      orElse: () => BookWithList(
        book: book,
        listId: _selectedListId ?? '',
        listName: _selectedListName,
      ),
    );

    showModalBottomSheet<Widget>(
      context: _buildContext,
      isScrollControlled: true,
      builder: (BuildContext modalContext) => isScanned
          ? ScanBookDetailsCard(
              book: book,
              bookService: BookService(modalContext),
              lists: {_selectedListId ?? '': _selectedListName ?? ''},
            )
          : BookDetailsCard(
              book: book,
              bookService: BookService(modalContext),
              listId: _selectedListId ?? '',
              listName: _selectedListName ?? '',
            ),
    );
  }

  Future<void> _addBookToList(Book book, String listId) async {
    try {
      await _bookService!.addBookToList(book, listId);
      if (!mounted) return;
      ScaffoldMessenger.of(_buildContext).showSnackBar(
        const SnackBar(content: Text('Book added successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(_buildContext).showSnackBar(
        SnackBar(content: Text('Error adding book: $e')),
      );
    }
  }

  void _onBookTap(BuildContext context, Book book) {
    _showBookDetails(book, isScanned: false);
  }

  Future<void> _loadCachedProfileImage() async {
    print('Loading cached profile image');
    final prefs = await SharedPreferences.getInstance();
    final cachedImage = prefs.getString('cachedProfileImage');
    final lastUpdate = prefs.getInt('lastImageUpdate');

    if (cachedImage != null) {
      print('Found cached profile image');
      if (mounted) {
        setState(() {
          _cachedProfileImage = cachedImage;
          _isProfileImageLoading = false;
        });
      }
      return;
    }

    print('No cached profile image found');
    if (mounted) {
      setState(() {
        _isProfileImageLoading = false;
      });
    }
  }

  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
      _lastBackPressTime = now;
      ScaffoldMessenger.of(_buildContext).showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    return true;
  }
}
