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
import '../screens/search_screen.dart';
import 'package:http/http.dart' as http;

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
  String _selectedListName = 'Library';
  final _fabKey = GlobalKey<ExpandableFabState>();
  String? _errorMessage;
  bool _isLoading = true;
  bool _isExpandedStatesLoaded = false;
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
  Future<void>? _listManagerInitialization;
  bool _hasUnreadNotifications = false;
  int _notificationCount = 0;
  StreamSubscription<QuerySnapshot>? _notificationsSubscription;
  bool _isMenuOpen = false;
  double _menuWidth = 280.0;
  double _dragStartX = 0.0;
  double _currentDragX = 0.0;
  Widget? _cachedBookList;

  // Services
  late final DatabaseService _databaseService;
  late final BookCacheService _bookCacheService;
  late final BookLoadingService _bookLoadingService;
  late final BookSortingService _bookSortingService;

  // Custom FAB location
  static const _kFloatingActionButtonLocation =
      _CustomFloatingActionButtonLocation();

  // Navigation helper
  Future<void> _navigateToRoute(String routeName) async {
    print('Navigating to $routeName');

    // Close the menu first
    setState(() {
      _isMenuOpen = false;
      _currentDragX = 0.0;
    });

    print('Menu closed, waiting for animation to complete');
    // Wait for the animation to complete
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) {
      print('Widget no longer mounted, navigation canceled');
      return;
    }

    print('Navigation proceeding to $routeName with context: $_buildContext');
    try {
      // Use a direct navigation approach
      Navigator.pushNamed(_buildContext, routeName);
      print('Navigation command executed');
    } catch (e) {
      print('Navigation error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    print('HomeScreen initState called');

    // Ensure menu is closed by default
    _isMenuOpen = false;
    _currentDragX = 0.0;

    // Initialize services first
    _initializeFirestore();
    _initializeDatabase();
    _ensureIndexes();
    _loadCachedProfileImage();
    _listenToNotifications();

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
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        print('Auth state changed: ${user?.uid ?? "No user"}');
        if (user != null && mounted) {
          print('New user authenticated, initializing...');
          _initializeDefaultList().then((_) {
            print('Default list initialized, loading books...');
            _loadBooks();
          });
        }
      },
      onError: (e, stackTrace) {
        print('Error in auth state listener: $e');
        print('Stack trace: $stackTrace');
        if (mounted) {
          ErrorService.setError(
            'Authentication error: $e. Please sign in again.',
          );
          setState(() {
            _isLoading = false;
          });
        }
      },
    );

    _loadSortPreference();
  }

  Future<void> _initializeListManager(BuildContext context) async {
    if (_listManager == null) {
      _listManager = ListManager(context);
      await _listManager?.loadExpandedStates();
      // Add a delay to ensure all states are properly initialized
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        setState(() {
          _isExpandedStatesLoaded = true;
        });
      }
    }
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
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      print('Error caching list: $e');
    }
  }

  Future<List<BookWithList>> _getCachedBooks(String listId) async {
    if (_database == null) return [];

    try {
      final List<Map<String, dynamic>> maps = await _database!.query(
        'books',
        where: listId == 'Library' ? null : 'listId = ?',
        whereArgs: listId == 'Library' ? null : [listId],
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
    _notificationsSubscription?.cancel();
    print('HomeScreen dispose: Canceled auth subscription and list manager');
    super.dispose();
  }

  Future<void> _initializeDefaultList() async {
    if (!mounted) return;
    print('Initializing default list');

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('No authenticated user found');
      return;
    }

    print('Authenticated user: UID=${user.uid}, email=${user.email}');

    try {
      print('Creating/updating user document');
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('Checking for Library list');
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .where('name', isEqualTo: 'Library')
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        print('Creating new Library list');
        final listRef = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .add(
                {'name': 'Library', 'createdAt': FieldValue.serverTimestamp()});
        print('Created Library list with ID: ${listRef.id}');
        if (mounted) {
          setState(() {
            _selectedListId = listRef.id;
            _selectedListName = 'Library';
          });
        }
      } else {
        print('Found existing Library list with ID: ${snapshot.docs.first.id}');
        if (mounted) {
          setState(() {
            _selectedListId = snapshot.docs.first.id;
            _selectedListName = 'Library';
          });
        }
      }
    } catch (e, stackTrace) {
      print('Error initializing default list: $e');
      print('Stack trace: $stackTrace');
    }
  }

  // Add method to clear the book list cache
  void _clearBookListCache() {
    _cachedBookList = null;
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

          ScaffoldMessenger.of(
            _buildContext,
          ).showSnackBar(SnackBar(content: Text('Created new list: $result')));
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              _buildContext,
            ).showSnackBar(SnackBar(content: Text('Error creating list: $e')));
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
          'Are you sure you want to delete this list and all its books?',
        ),
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

            // If we're currently viewing the deleted list, switch to Library
            if (_selectedListId == listId) {
              _selectedListId = null;
              _selectedListName = 'Library';
            }
          }

          // Reload the current view
          if (_selectedListId == null) {
            await _initializeDefaultList();
          }
          await _loadBooks();

          ScaffoldMessenger.of(_buildContext).showSnackBar(
            const SnackBar(
              content: Text('List and all its books deleted successfully'),
            ),
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              _buildContext,
            ).showSnackBar(SnackBar(content: Text('Error deleting list: $e')));
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
            // If we're in Library view or the list we just added to, update the UI
            if (_selectedListName == 'Library' ||
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

                // If we're in Library view, we need to reload all books
                if (_selectedListName == 'Library') {
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
          ScaffoldMessenger.of(
            _buildContext,
          ).showSnackBar(SnackBar(content: Text('Error adding book: $e')));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        _buildContext,
      ).showSnackBar(SnackBar(content: Text('Error loading lists: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    _buildContext = context;
    _bookService ??= BookService(context);

    if (_listManagerInitialization == null) {
      _listManagerInitialization = _initializeListManager(context);
    }

    return FutureBuilder<void>(
      future: _listManagerInitialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !_isExpandedStatesLoaded ||
            _isLoading) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = FirebaseAuth.instance.currentUser;
        print(
            'Building HomeScreen for user: ${user?.email ?? "No user"}, UID: ${user?.uid ?? "No UID"}');
        print(
            'Selected List: $_selectedListName, ID: $_selectedListId, Sort: $_sortPreference');
        print('Menu state: isOpen=$_isMenuOpen, dragX=$_currentDragX');

        // Cache the book list if it's not already cached
        if (_cachedBookList == null && !_isLoading && _errorMessage == null) {
          _cachedBookList = _buildBookList();
        }

        return WillPopScope(
          onWillPop: _onWillPop,
          child: Scaffold(
            body: Stack(
              children: [
                // Main Content
                Positioned.fill(
                  child: Material(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Column(
                      children: [
                        AppBar(
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
                              PopupMenuItem<String>(
                                enabled: false,
                                height: 0,
                                padding: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: Divider(height: 1),
                                ),
                              ),
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
                                  : Stack(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundImage:
                                              _cachedProfileImage != null
                                                  ? MemoryImage(base64Decode(
                                                      _cachedProfileImage!))
                                                  : null,
                                          child: _cachedProfileImage == null
                                              ? const Icon(Icons.person)
                                              : null,
                                        ),
                                        if (_hasUnreadNotifications)
                                          Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              width: 12,
                                              height: 12,
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .scaffoldBackgroundColor,
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                              onSelected: (String value) {
                                switch (value) {
                                  case 'profile':
                                    _navigateToRoute('/profile');
                                    break;
                                  case 'search':
                                    _navigateToRoute('/search');
                                    break;
                                  case 'notifications':
                                    _navigateToRoute('/notifications');
                                    break;
                                  case 'messages':
                                    _navigateToRoute('/messages');
                                    break;
                                  case 'settings':
                                    _navigateToRoute('/settings');
                                    break;
                                  case 'logout':
                                    _showLogoutDialog();
                                    break;
                                }
                              },
                              constraints: BoxConstraints(
                                minWidth: MediaQuery.of(context).size.width,
                                maxWidth: MediaQuery.of(context).size.width,
                              ),
                              position: PopupMenuPosition.under,
                              offset: const Offset(0, 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              itemBuilder: (BuildContext context) =>
                                  <PopupMenuEntry<String>>[
                                PopupMenuItem(
                                  value: 'profile',
                                  child: Row(
                                    children: [
                                      Icon(Icons.person,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                      const SizedBox(width: 8),
                                      const Text('Go to Profile'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'search',
                                  child: Row(
                                    children: [
                                      Icon(Icons.search,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                      const SizedBox(width: 8),
                                      const Text('Search'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'notifications',
                                  child: Row(
                                    children: [
                                      Icon(Icons.notifications,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                      const SizedBox(width: 8),
                                      const Text('Notifications'),
                                      if (_hasUnreadNotifications) ...[
                                        const Spacer(),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            _notificationCount > 100
                                                ? '100+'
                                                : '$_notificationCount',
                                            style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'messages',
                                  child: Row(
                                    children: [
                                      Icon(Icons.message,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                      const SizedBox(width: 8),
                                      const Text('Messages'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'settings',
                                  child: Row(
                                    children: [
                                      Icon(Icons.settings,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                      const SizedBox(width: 8),
                                      const Text('Settings'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  enabled: false,
                                  height: 0,
                                  padding: EdgeInsets.zero,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    child: Divider(height: 1),
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'logout',
                                  child: Row(
                                    children: [
                                      Icon(Icons.logout,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                      const SizedBox(width: 8),
                                      const Text('Logout'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Expanded(
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : _errorMessage != null
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
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
                                        ],
                                      ),
                                    )
                                  : _selectedListName == 'Library' &&
                                          _loadedBooks.isEmpty &&
                                          _cachedBookList == null
                                      ? _buildBookList()
                                      : _cachedBookList ?? _buildBookList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            floatingActionButtonLocation:
                FloatingActionButtonLocation.endDocked,
            floatingActionButton: Container(
              margin: const EdgeInsets.only(bottom: 0.0),
              child: ExpandableFab(
                key: _fabKey,
                distance: 112.0,
                type: ExpandableFabType.fan,
                fanAngle: 90,
                openButtonBuilder: RotateFloatingActionButtonBuilder(
                  child: const Icon(Icons.add),
                  fabSize: ExpandableFabSize.regular,
                  shape: const CircleBorder(),
                  angle: 3.14 * 2,
                  backgroundColor:
                      Color.lerp(widget.accentColor, Colors.black, 0.03),
                ),
                closeButtonBuilder: RotateFloatingActionButtonBuilder(
                  child: const Icon(Icons.close),
                  fabSize: ExpandableFabSize.regular,
                  shape: const CircleBorder(),
                  angle: 3.14 * 2,
                  backgroundColor:
                      Color.lerp(widget.accentColor, Colors.black, 0.03),
                ),
                children: [
                  FloatingActionButton(
                    heroTag: 'fab_1',
                    mini: true,
                    child: const Icon(Icons.search),
                    backgroundColor:
                        Color.lerp(widget.accentColor, Colors.black, 0.03),
                    onPressed: () {
                      final state = _fabKey.currentState;
                      if (state != null) {
                        state.toggle();
                      }
                      print('Showing search sheet');
                      _showBookSearchSheet();
                    },
                  ),
                  FloatingActionButton(
                    heroTag: 'fab_2',
                    mini: true,
                    child: const Icon(Icons.text_snippet),
                    backgroundColor:
                        Color.lerp(widget.accentColor, Colors.black, 0.03),
                    onPressed: () async {
                      final state = _fabKey.currentState;
                      if (state != null) {
                        state.toggle();
                      }
                      print('Starting text scan');
                      await scanTextFromImage();
                    },
                  ),
                  FloatingActionButton(
                    heroTag: 'fab_3',
                    mini: true,
                    child: const Icon(Icons.link),
                    backgroundColor:
                        Color.lerp(widget.accentColor, Colors.black, 0.03),
                    onPressed: () async {
                      final state = _fabKey.currentState;
                      if (state != null) {
                        state.toggle();
                      }
                      print('Opening link input dialog');
                      await _showLinkInputDialog();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
      // Index for Library view books query
      await FirebaseFirestore.instance.collection('users').doc('_indexes').set({
        'indexes': {
          'books_library': {
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
      if (_selectedListName == 'Library') {
        await _fetchListNames(user.uid);
      }

      Query query;
      if (_selectedListName == 'Library') {
        print('Executing Firestore query for Library');
        // For Library view, get all books from all lists
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
      final totalBooks = querySnapshot.docs.length;
      await settings.updateBookCounts(totalBooks, settings.readBooks);
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

        String listName = 'Unknown List';
        String listId = '';

        if (_selectedListName == 'Library') {
          final path = doc.reference.path;
          final parts = path.split('/');
          if (parts.length >= 4) {
            listId = parts[3];
            listName = _listNamesCache[listId] ?? 'Unknown List';
          }
        } else {
          listId = _selectedListId!;
          listName = _selectedListName;
        }

        _loadedBooks.add(
          BookWithList(book: book, listId: listId, listName: listName),
        );
      }

      // Sort books based on current sort order
      _sortBooks();

      print('Successfully processed ${_loadedBooks.length} books');

      // Force a UI update
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
          _cachedBookList = _buildBookList();
        });
      }
    } catch (e) {
      print('Error loading books: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null; // Don't show error message
          _cachedBookList = _buildBookList();
        });
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
              _selectedListName = 'Library';
            });
            // First ensure we have the Library list initialized
            await _initializeDefaultList();
            // Then load the books
            await _loadBooks();
          }
        },
        child: const ListTile(title: Text('Library')),
      ),
      PopupMenuItem<String>(
        enabled: false,
        height: 0,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Divider(height: 1),
        ),
      ),
      PopupMenuItem<String>(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseAuth.instance.currentUser != null
              ? FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .collection('lists')
                  .where('name', isNotEqualTo: 'Library')
                  .orderBy('name')
                  .orderBy('createdAt')
                  .snapshots()
              : Stream.empty(),
          builder: (
            BuildContext streamContext,
            AsyncSnapshot<QuerySnapshot> snapshot,
          ) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const ListTile(title: Text('Loading lists...'));
            }

            if (snapshot.hasError) {
              return ListTile(title: Text('Error: ${snapshot.error}'));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const ListTile(title: Text('No lists found'));
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

      final isbn = await BarcodeService.scanBarcode();

      if (isbn == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'No barcode found. Please try again.';
          _isLoading = false;
        });
        return;
      }

      // Process the scanned ISBN
      _processScannedISBN(isbn);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error scanning barcode: $e';
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        _buildContext,
      ).showSnackBar(SnackBar(content: Text('Error scanning barcode: $e')));
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
              onClose: () {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                  });
                }
              },
            )
          : BookDetailsCard(
              book: book,
              bookService: BookService(modalContext),
              listId: _selectedListId,
              listName: _selectedListName,
              actualListId: bookWithList.listId,
            ),
    ).whenComplete(() {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _addBookToList(Book book, String listId) async {
    try {
      await _bookService!.addBookToList(book, listId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        _buildContext,
      ).showSnackBar(const SnackBar(content: Text('Book added successfully')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        _buildContext,
      ).showSnackBar(SnackBar(content: Text('Error adding book: $e')));
    }
  }

  void _onBookTap(BuildContext context, Book book) {
    _showBookDetails(book, isScanned: false);
  }

  Future<void> _loadCachedProfileImage() async {
    print('Loading cached profile image');
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Use user-specific key for caching
    final userPrefix = 'user_${user.uid}_';
    final cachedImage = prefs.getString('${userPrefix}cachedProfileImage');
    final lastUpdate = prefs.getInt('${userPrefix}lastImageUpdate');

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

    print('No cached profile image found, checking Firebase');
    // If no cached image, check Firebase
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        final profileImage = data['profileImageBase64'] as String?;

        if (profileImage != null) {
          print('Found profile image in Firebase, caching it');
          // Cache the image
          await prefs.setString(
            '${userPrefix}cachedProfileImage',
            profileImage,
          );
          await prefs.setInt(
            '${userPrefix}lastImageUpdate',
            DateTime.now().millisecondsSinceEpoch,
          );

          if (mounted) {
            setState(() {
              _cachedProfileImage = profileImage;
              _isProfileImageLoading = false;
            });
          }
          return;
        }
      }
    } catch (e) {
      print('Error loading profile image from Firebase: $e');
    }

    print('No profile image found in Firebase');
    if (mounted) {
      setState(() {
        _isProfileImageLoading = false;
      });
    }
  }

  Future<bool> _onWillPop() async {
    // First check if the FAB is expanded, if so, collapse it
    final fabState = _fabKey.currentState;
    if (fabState != null && fabState.isOpen) {
      fabState.toggle();
      return false;
    }

    // Otherwise handle back press as normal
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

  void _showLogoutDialog() {
    showDialog(
      context: _buildContext,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _listenToNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _notificationsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('notifications')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _hasUnreadNotifications = snapshot.docs.isNotEmpty;
          _notificationCount = snapshot.docs.length;
        });
      }
    });
  }

  Widget _buildBookList() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    // For Library view, make sure we're querying using an actual list ID
    if (_selectedListName == 'Library' && _selectedListId == null) {
      // Create a temporary loading widget while we find the Library list ID
      _initializeDefaultList();
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _selectedListName == 'Library'
          ? FirebaseFirestore.instance
              .collectionGroup('books')
              .where('userId', isEqualTo: user.uid)
              .orderBy('createdAt', descending: true)
              .snapshots()
          : FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('lists')
              .doc(_selectedListId)
              .collection('books')
              .orderBy('createdAt', descending: true)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          print('StreamBuilder error: ${snapshot.error}');
          return const Center(child: Text('No books found'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          // If we have cached books, show them while loading
          if (_loadedBooks.isNotEmpty) {
            return _buildBookListView(_loadedBooks);
          }
          return const Center(child: CircularProgressIndicator());
        }

        final books = snapshot.data?.docs ?? [];
        if (books.isEmpty) {
          return const Center(child: Text('No books found'));
        }

        final groupedBooks = <String, List<BookWithList>>{};
        for (var doc in books) {
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

          String listName = 'Unknown List';
          String listId = '';

          if (_selectedListName == 'Library') {
            final path = doc.reference.path;
            final parts = path.split('/');
            if (parts.length >= 4) {
              listId = parts[3];
              listName = _listNamesCache[listId] ?? 'Unknown List';
            }
          } else {
            listId = _selectedListId!;
            listName = _selectedListName;
          }

          groupedBooks.putIfAbsent(listName, () => []).add(
                BookWithList(book: book, listId: listId, listName: listName),
              );
        }

        // Update the loaded books cache
        _loadedBooks = groupedBooks.values.expand((books) => books).toList();
        _sortBooks();

        return _buildBookListView(_loadedBooks);
      },
    );
  }

  Widget _buildBookListView(List<BookWithList> books) {
    final groupedBooks = <String, List<BookWithList>>{};
    for (var book in books) {
      groupedBooks.putIfAbsent(book.listName, () => []).add(book);
    }

    final sortedListNames = groupedBooks.keys.toList()..sort();
    final displayItems = <dynamic>[];
    for (var listName in sortedListNames) {
      displayItems.add(listName);
      if (_listManager?.expandedLists[listName] ?? true) {
        displayItems.addAll(groupedBooks[listName]!);
      }
    }

    return ListView.builder(
      itemCount: displayItems.length + 1,
      itemBuilder: (BuildContext listContext, int index) {
        if (index == 0) {
          return const SizedBox(height: 15);
        }
        final item = displayItems[index - 1];
        if (item is String) {
          final listName = item;
          final bookCount = groupedBooks[listName]?.length ?? 0;
          final isExpanded = _listManager?.expandedLists[listName] ?? true;
          final animation = _listManager?.getAnimationForList(listName, this) ??
              AlwaysStoppedAnimation(1.0);

          return ListItem(
            listName: listName,
            bookCount: bookCount,
            books: groupedBooks[listName],
            isExpanded: isExpanded,
            animation: animation,
            accentColor: widget.accentColor,
            onToggleExpanded: (name) =>
                _listManager?.toggleListExpanded(name, this),
            onBookTap: _onBookTap,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _showBookSearchSheet() {
    if (_bookService != null) {
      BookSearchSheet.show(
        _buildContext,
        _selectedListId,
        _selectedListName,
        _bookService!,
      );
    }
  }

  Future<void> scanTextFromImage() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final isbn = await TextRecognitionService.scanISBN();
      if (isbn == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(_buildContext).showSnackBar(
          const SnackBar(content: Text('No ISBN found. Please try again.')),
        );
        return;
      }

      // Process the scanned ISBN
      await _processScannedISBN(isbn);
    } catch (e) {
      print('Error scanning text: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error scanning text: $e';
        });
        ScaffoldMessenger.of(_buildContext).showSnackBar(
          SnackBar(content: Text('Error scanning text: $e')),
        );
      }
    }
  }

  Future<void> _processScannedISBN(String isbn) async {
    try {
      // Check cache first
      final cachedBook = await _getCachedBook(isbn);
      if (cachedBook != null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
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
      setState(() {
        _isLoading = false;
      });
      _showBookDetails(book, isScanned: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error processing ISBN: $e';
        _isLoading = false;
      });
      ScaffoldMessenger.of(_buildContext)
          .showSnackBar(SnackBar(content: Text('Error processing ISBN: $e')));
    }
  }

  Future<void> _showLinkInputDialog() async {
    final TextEditingController controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    return showDialog(
      context: _buildContext,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Paste Book Link'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Paste Amazon, Google Books, AbeBooks, or eBay link',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a link';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext);
                await _processBookLink(controller.text);
              }
            },
            child: const Text('Process'),
          ),
        ],
      ),
    );
  }

  Future<void> _processBookLink(String url) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Extract ISBN or title from URL
      String? isbn;
      String? title;

      // Amazon URL patterns
      final amazonPatterns = [
        RegExp(r'amazon\.[^/]+/.*?/(\d{9}[\dX])'), // Standard ISBN pattern
        RegExp(r'amazon\.[^/]+/.*?/dp/([A-Z0-9]{10})'), // ASIN pattern
        RegExp(
            r'amazon\.[^/]+/.*?/product/([A-Z0-9]{10})'), // Product ID pattern
        RegExp(r'amazon\.[^/]+/.*?/title/([^/]+)'), // Title pattern
      ];

      // Google Books URL patterns
      final googlePatterns = [
        RegExp(
            r'books\.google\.[^/]+/books\?.*?isbn=(\d{9}[\dX])'), // ISBN pattern
        RegExp(r'books\.google\.[^/]+/books\?.*?id=([^&]+)'), // Book ID pattern
        RegExp(
            r'books\.google\.[^/]+/books\?.*?title=([^&]+)'), // Title pattern
      ];

      // AbeBooks URL patterns
      final abePatterns = [
        RegExp(r'abebooks\.[^/]+/.*?/(\d{9}[\dX])'), // ISBN pattern
        RegExp(r'abebooks\.[^/]+/.*?/title/([^/]+)'), // Title pattern
        RegExp(r'abebooks\.[^/]+/.*?/dp/([A-Z0-9]{10})'), // ASIN pattern
        RegExp(
            r'abebooks\.[^/]+/.*?/product/([A-Z0-9]{10})'), // Product ID pattern
        RegExp(
            r'abebooks\.[^/]+/.*?/search/.*?/([^/]+)'), // Search result pattern
      ];

      // Try to find ISBN or title from Amazon
      for (var pattern in amazonPatterns) {
        final match = pattern.firstMatch(url);
        if (match != null) {
          final value = match.group(1);
          if (value != null) {
            if (value.length == 10 || value.length == 13) {
              isbn = value;
            } else {
              title = Uri.decodeComponent(value.replaceAll('-', ' '));
            }
            break;
          }
        }
      }

      // Try to find ISBN or title from Google Books
      if (isbn == null && title == null) {
        for (var pattern in googlePatterns) {
          final match = pattern.firstMatch(url);
          if (match != null) {
            final value = match.group(1);
            if (value != null) {
              if (value.length == 10 || value.length == 13) {
                isbn = value;
              } else {
                title = Uri.decodeComponent(value.replaceAll('-', ' '));
              }
              break;
            }
          }
        }
      }

      // Try to find ISBN or title from AbeBooks
      if (isbn == null && title == null) {
        for (var pattern in abePatterns) {
          final match = pattern.firstMatch(url);
          if (match != null) {
            final value = match.group(1);
            if (value != null) {
              if (value.length == 10 || value.length == 13) {
                isbn = value;
              } else {
                title = Uri.decodeComponent(value.replaceAll('-', ' '));
              }
              break;
            }
          }
        }
      }

      // If we couldn't find ISBN or title in the URL, try scraping the website
      if (isbn == null && title == null) {
        try {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            final html = response.body;

            // Try to find ISBN in the HTML
            final isbnPatterns = [
              RegExp('ISBN[-\s]*(?:13|10)?[-\s]*[:=]?\s*(\\d{9}[\\dX])',
                  caseSensitive: false),
              RegExp(
                  'ISBN[-\s]*(?:13|10)?[-\s]*[:=]?\s*(\\d{3}[- ]?\\d{1,5}[- ]?\\d{1,7}[- ]?\\d{1,6}[- ]?\\d)',
                  caseSensitive: false),
              RegExp('data-isbn=["\'](\\d{9}[\\dX])["\']',
                  caseSensitive: false),
              RegExp(
                  'itemprop=["\']isbn["\']\s*content=["\'](\\d{9}[\\dX])["\']',
                  caseSensitive: false),
              // AbeBooks specific patterns
              RegExp('class=["\']isbn["\']>.*?(\\d{9}[\\dX])<',
                  caseSensitive: false),
              RegExp('ISBN-13:.*?(\\d{9}[\\dX])', caseSensitive: false),
              RegExp('ISBN-10:.*?(\\d{9}[\\dX])', caseSensitive: false),
              RegExp('data-isbn-13=["\'](\\d{9}[\\dX])["\']',
                  caseSensitive: false),
              RegExp('data-isbn-10=["\'](\\d{9}[\\dX])["\']',
                  caseSensitive: false),
            ];

            for (var pattern in isbnPatterns) {
              final match = pattern.firstMatch(html);
              if (match != null) {
                final value = match.group(1);
                if (value != null) {
                  isbn = value.replaceAll(RegExp('[-\s]'), '');
                  break;
                }
              }
            }

            // If no ISBN found, try to find the title
            if (isbn == null) {
              final titlePatterns = [
                RegExp('<h1[^>]*>(.*?)</h1>', caseSensitive: false),
                RegExp('<title>(.*?)</title>', caseSensitive: false),
                RegExp('itemprop=["\']name["\']\s*content=["\'](.*?)["\']',
                    caseSensitive: false),
                RegExp('data-title=["\'](.*?)["\']', caseSensitive: false),
                // AbeBooks specific patterns
                RegExp('class=["\']title["\']>.*?<span[^>]*>(.*?)</span>',
                    caseSensitive: false),
                RegExp('class=["\']book-title["\']>(.*?)</',
                    caseSensitive: false),
                RegExp('data-title=["\'](.*?)["\']', caseSensitive: false),
                RegExp('class=["\']product-title["\']>(.*?)</',
                    caseSensitive: false),
              ];

              for (var pattern in titlePatterns) {
                final match = pattern.firstMatch(html);
                if (match != null) {
                  final value = match.group(1);
                  if (value != null) {
                    // Clean up the title
                    title = value
                        .replaceAll(RegExp('<[^>]*>'), '') // Remove HTML tags
                        .replaceAll(
                            RegExp('&[^;]+;'), '') // Remove HTML entities
                        .replaceAll(RegExp('\\s+'), ' ') // Normalize whitespace
                        .trim();

                    // Remove common suffixes like "| AbeBooks" or "- Google Books"
                    title = title.replaceAll(RegExp('\\s*[|]\\s*.*\$'), '');
                    title = title.replaceAll(RegExp('\\s*-\\s*.*\$'), '');
                    title =
                        title.replaceAll(RegExp('\\s*\\|\\s*AbeBooks.*\$'), '');
                    title = title.replaceAll(RegExp('\\s*\\|\\s*Book.*\$'), '');
                    break;
                  }
                }
              }
            }

            // If still no title found, try to extract from meta tags
            if (isbn == null && title == null) {
              final metaPatterns = [
                RegExp(
                    '<meta[^>]*name=["\']description["\'][^>]*content=["\'](.*?)["\']',
                    caseSensitive: false),
                RegExp(
                    '<meta[^>]*property=["\']og:title["\'][^>]*content=["\'](.*?)["\']',
                    caseSensitive: false),
                RegExp(
                    '<meta[^>]*name=["\']keywords["\'][^>]*content=["\'](.*?)["\']',
                    caseSensitive: false),
              ];

              for (var pattern in metaPatterns) {
                final match = pattern.firstMatch(html);
                if (match != null) {
                  final value = match.group(1);
                  if (value != null) {
                    // Clean up the title
                    title = value
                        .replaceAll(RegExp('<[^>]*>'), '')
                        .replaceAll(RegExp('&[^;]+;'), '')
                        .replaceAll(RegExp('\\s+'), ' ')
                        .trim();

                    // Remove common suffixes
                    title = title.replaceAll(RegExp('\\s*[|]\\s*.*\$'), '');
                    title = title.replaceAll(RegExp('\\s*-\\s*.*\$'), '');
                    title =
                        title.replaceAll(RegExp('\\s*\\|\\s*AbeBooks.*\$'), '');
                    title = title.replaceAll(RegExp('\\s*\\|\\s*Book.*\$'), '');
                    break;
                  }
                }
              }
            }
          }
        } catch (e) {
          print('Error scraping website: $e');
        }
      }

      if (isbn != null) {
        // Process the ISBN using existing functionality
        await _processScannedISBN(isbn);
      } else if (title != null) {
        // Search by title
        final book = await _bookService!.searchBookByTitle(title);
        if (book != null) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
          });
          _showBookDetails(book, isScanned: true);
        } else {
          throw Exception('Could not find book with title: $title');
        }
      } else {
        throw Exception('Could not find ISBN or title in the provided link');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error processing link: $e';
        });
        ScaffoldMessenger.of(_buildContext).showSnackBar(
          SnackBar(content: Text('Error processing link: $e')),
        );
      }
    }
  }
}

class _CustomFloatingActionButtonLocation extends FloatingActionButtonLocation {
  const _CustomFloatingActionButtonLocation();

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry scaffoldGeometry) {
    final double contentBottom = scaffoldGeometry.contentBottom;
    final double bottomContentHeight =
        scaffoldGeometry.scaffoldSize.height - contentBottom;
    final double bottomViewPadding = scaffoldGeometry.minViewPadding.bottom;
    final double fabY = contentBottom - 20.0 - bottomViewPadding;
    return Offset(
      scaffoldGeometry.scaffoldSize.width -
          16.0 -
          scaffoldGeometry.minInsets.right,
      fabY,
    );
  }
}
