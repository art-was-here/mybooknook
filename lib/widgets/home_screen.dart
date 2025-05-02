import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../services/book_service.dart';
import 'book_search_sheet.dart';
import 'book_details_card.dart';
import 'dart:async';

// Helper class to store book and its list information
class BookWithList {
  final Book book;
  final String listId;
  final String listName;

  BookWithList(
      {required this.book, required this.listId, required this.listName});
}

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

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedListId;
  String _selectedListName = 'Home';
  final _fabKey = GlobalKey<ExpandableFabState>();
  String? _errorMessage;
  bool _isLoading = true;
  late BookService _bookService;
  StreamSubscription<User?>? _authSubscription;
  String _sortPreference = 'title';

  @override
  void initState() {
    super.initState();
    _bookService = BookService(context);
    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: false);
    _loadSortPreference().then((_) async {
      await _migrateBooks();
      await _cleanupStrayBooks();
    });
    print('HomeScreen initState: Waiting for auth state');
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && mounted) {
        print(
            'HomeScreen initState: User authenticated: ${user.uid}, email: ${user.email}');
        _initializeDefaultList();
      }
    }, onError: (e, stackTrace) {
      if (mounted) {
        print('HomeScreen initState: Error waiting for auth state: $e');
        print('Stack trace: $stackTrace');
        setState(() {
          _errorMessage = 'Authentication error: $e. Please sign in again.';
          _isLoading = false;
        });
      }
    });
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
            await bookDoc.reference.update(updates);
            print('Updated book ${bookDoc.id} in list ${listDoc.id}: $updates');
          } else {
            print('No update needed for book ${bookDoc.id}');
          }
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
      for (var bookDoc in booksSnapshot.docs) {
        final path = bookDoc.reference.path;
        if (!path.contains('/users/${user.uid}/lists/')) {
          print('Found stray book at path: $path');
          await bookDoc.reference.delete();
          print('Deleted stray book: ${bookDoc.id} at $path');
        } else {
          print('Valid book at path: $path');
        }
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
    print('HomeScreen dispose: Canceled auth subscription');
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
      if (mounted) {
        print('No authenticated user found');
        setState(() {
          _errorMessage = 'No authenticated user. Please sign in again.';
          _isLoading = false;
        });
      }
      return;
    }
    print('Authenticated user: UID=${user.uid}, email=${user.email}');
    try {
      print('Forcing authentication token refresh');
      await user.getIdToken(true);
      print('Token refreshed successfully');

      print('Creating user document at /users/${user.uid}');
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
          {'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      print('User document created or updated successfully');

      print('Checking if lists collection exists at /users/${user.uid}/lists');
      try {
        final listsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .limit(1)
            .get();
        print(
            'Lists collection query result: ${listsSnapshot.docs.length} documents found');
      } catch (e, stackTrace) {
        print('Error querying lists collection: $e');
        print('Stack trace: $stackTrace');
        throw Exception('Failed to query lists collection: $e');
      }

      print('Querying for Home list at /users/${user.uid}/lists');
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .where('name', isEqualTo: 'Home')
            .limit(1)
            .get();
        print('Home query completed: ${snapshot.docs.length} list(s) found');
        if (snapshot.docs.isEmpty) {
          print('No Home list found, creating new list');
          final listRef = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('lists')
              .add({
            'name': 'Home',
            'createdAt': FieldValue.serverTimestamp(),
          });
          print('Created default list with ID: ${listRef.id}');
          if (mounted) {
            setState(() {
              _selectedListId = listRef.id;
              _selectedListName = 'Home';
            });
          }
        } else {
          print(
              'Found existing default list with ID: ${snapshot.docs.first.id}');
          if (mounted) {
            setState(() {
              _selectedListId = snapshot.docs.first.id;
              _selectedListName = 'Home';
            });
          }
        }
      } catch (e, stackTrace) {
        print('Error querying or creating Home list: $e');
        print('Stack trace: $stackTrace');
        if (mounted) {
          setState(() {
            _errorMessage = 'Failed to load lists: $e';
            if (e.toString().contains('permission-denied')) {
              _errorMessage =
                  'Permission denied accessing lists (Error Code: INIT). Please sign out and sign in again, or contact support if the issue persists.';
            }
          });
        }
        throw Exception('Failed to query or create Home list: $e');
      }

      if (_selectedListId == null && mounted) {
        print('Error: _selectedListId is still null after initialization');
        throw Exception('Failed to initialize default list ID');
      }
      print(
          'Initialization complete: _selectedListId=$_selectedListId, _selectedListName=$_selectedListName');
    } catch (e, stackTrace) {
      print('Error initializing default list: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load lists: $e';
          if (e.toString().contains('permission-denied')) {
            _errorMessage =
                'Permission denied accessing lists (Error Code: INIT). Please sign out and sign in again, or contact support if the issue persists.';
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      print('Initialization finished, _isLoading=false');
    }
  }

  Future<void> _addNewList() async {
    if (!mounted) return;
    print('Opening new list dialog');
    final TextEditingController controller = TextEditingController();
    final String? newListName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New List'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter list name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              print('Cancel new list');
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                print('Creating new list: ${controller.text.trim()}');
                Navigator.pop(context, controller.text.trim());
              } else {
                print('Empty list name');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('List name cannot be empty')),
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (newListName != null && mounted) {
      print('New list name received: $newListName');
      final user = FirebaseAuth.instance.currentUser!;
      try {
        print('Creating new list at /users/${user.uid}/lists');
        final listRef = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .add({
          'name': newListName,
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('New list created with ID: ${listRef.id}');
        if (mounted) {
          setState(() {
            _selectedListId = listRef.id;
            _selectedListName = newListName;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('List "$newListName" created')),
          );
        }
      } catch (e, stackTrace) {
        print('Error creating new list: $e');
        print('Stack trace: $stackTrace');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating list: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteList(String listId, String listName) async {
    if (!mounted) return;
    print('Attempting to delete list: $listName (ID: $listId)');
    if (listName == 'Home') {
      print('Cannot delete default list');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the default "Home" list')),
      );
      return;
    }

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete List'),
        content: Text(
            'Are you sure you want to delete "$listName" and all its books?'),
        actions: [
          TextButton(
            onPressed: () {
              print('Cancel delete list');
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              print('Confirm delete list: $listName');
              Navigator.pop(context, true);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmDelete == true && mounted) {
      print('Deleting list: $listName');
      final user = FirebaseAuth.instance.currentUser!;
      try {
        print('Deleting list at /users/${user.uid}/lists/$listId');
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .doc(listId)
            .delete();
        print('List deleted: $listName');
        if (_selectedListId == listId && mounted) {
          print('Selected list deleted, reinitializing default list');
          await _initializeDefaultList();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('List "$listName" deleted')),
          );
        }
      } catch (e, stackTrace) {
        print('Error deleting list: $e');
        print('Stack trace: $stackTrace');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting list: $e')),
          );
        }
      }
    }
  }

  Future<void> scanBarcode() async {
    if (!mounted) return;
    if (_selectedListId == null) {
      print('No list selected for barcode scan');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or create a list first')),
      );
      return;
    }

    try {
      print('Starting barcode scan');
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        print('Camera permission denied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission denied')),
          );
        }
        return;
      }

      var result = await BarcodeScanner.scan();
      String isbn = result.rawContent;
      print('Scanned ISBN: $isbn');

      if (isbn.isNotEmpty && mounted) {
        Book? book = await _bookService.fetchBookDetails(isbn);
        if (book != null) {
          print('Book found: ${book.title}');
          final user = FirebaseAuth.instance.currentUser!;
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('lists')
              .doc(_selectedListId)
              .collection('books')
              .doc(isbn)
              .set({
            ...book.toMap(),
            'userId': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
          });
          print('Book added via barcode: ${book.title}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text('Book added to $_selectedListName: ${book.title}')),
            );
          }
        } else {
          print('Book not found for ISBN: $isbn');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Book not found')),
            );
          }
        }
      } else {
        print('No ISBN scanned');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No ISBN detected')),
          );
        }
      }
    } catch (e, stackTrace) {
      print('Error during barcode scan: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error scanning barcode: $e')),
        );
      }
    }
  }

  List<PopupMenuEntry<String>> _buildListMenuItems() {
    print('Building list menu items');
    return [
      PopupMenuItem<String>(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseAuth.instance.currentUser != null
              ? FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .collection('lists')
                  .orderBy('createdAt')
                  .snapshots()
              : Stream.empty(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              print('List menu: Waiting for data');
              return const ListTile(
                title: Text('Loading lists...'),
              );
            }
            if (snapshot.hasError) {
              print('List menu error: ${snapshot.error}');
              print('Stack trace: ${snapshot.stackTrace}');
              String errorMessage = 'Error loading lists: ${snapshot.error}';
              if (snapshot.error.toString().contains('permission-denied')) {
                errorMessage =
                    'Permission denied loading lists (Error Code: MENU). Please sign out and sign in again.';
              }
              return ListTile(
                title: Text(errorMessage),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    if (mounted) {
                      print('Retrying list menu load');
                      setState(() {});
                    }
                  },
                ),
              );
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              print('List menu: No lists found');
              return const ListTile(
                title: Text('No lists available'),
              );
            }
            print('List menu: Lists found: ${snapshot.data!.docs.length}');
            return Column(
              children: snapshot.data!.docs.map((doc) {
                final listId = doc.id;
                final listName = doc['name'] as String;
                return PopupMenuItem<String>(
                  value: listId,
                  onTap: () {
                    print('Selected list: $listName (ID: $listId)');
                    if (mounted) {
                      setState(() {
                        _selectedListId = listId;
                        _selectedListName = listName;
                      });
                    }
                  },
                  child: ListTile(
                    title: Text(listName),
                    trailing: listName == 'Home'
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              print('Delete list button pressed: $listName');
                              _deleteList(listId, listName);
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    print(
        'Building HomeScreen for user: ${user?.email ?? "No user"}, UID: ${user?.uid ?? "No UID"}');
    print(
        'Selected List: $_selectedListName, ID: $_selectedListId, Sort: $_sortPreference');
    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'add_list' && mounted) {
              print('Add new list selected');
              await _addNewList();
            }
          },
          itemBuilder: (context) => [
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
            ..._buildListMenuItems(),
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
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              print('Navigating to settings');
              Navigator.pushNamed(context, '/settings');
            },
            tooltip: 'Settings',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'sign_out' && mounted) {
                print('Signing out user: ${user?.email ?? "No user"}');
                FirebaseAuth.instance.signOut();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'sign_out',
                child: Text('Sign out (${user?.email ?? "No user"})'),
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
                          const Text('Failed to load list. Please try again.'),
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
                  : FutureBuilder<Map<String, String>>(
                      future: _fetchListNames(user!.uid),
                      builder: (context, listNamesSnapshot) {
                        if (listNamesSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          print('FutureBuilder: Waiting for list names');
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (listNamesSnapshot.hasError) {
                          print(
                              'FutureBuilder error: ${listNamesSnapshot.error}');
                          print('Stack trace: ${listNamesSnapshot.stackTrace}');
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                    'Error loading lists: ${listNamesSnapshot.error}'),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    if (mounted) {
                                      print('Retrying list names fetch');
                                      setState(() {});
                                    }
                                  },
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          );
                        }
                        final listNames = listNamesSnapshot.data ?? {};
                        print(
                            'FutureBuilder: List names loaded: ${listNames.length} lists');

                        return StreamBuilder<QuerySnapshot>(
                          stream: _selectedListName == 'Home' && user != null
                              ? FirebaseFirestore.instance
                                  .collectionGroup('books')
                                  .where('userId', isEqualTo: user.uid)
                                  .orderBy(
                                    _sortPreference == 'date_added'
                                        ? 'createdAt'
                                        : _sortPreference == 'release_date'
                                            ? 'publishedDate'
                                            : _sortPreference,
                                    descending: _sortPreference ==
                                                'date_added' ||
                                            _sortPreference == 'release_date'
                                        ? true
                                        : false,
                                  )
                                  .snapshots()
                              : user != null
                                  ? FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(user.uid)
                                      .collection('lists')
                                      .doc(_selectedListId)
                                      .collection('books')
                                      .orderBy(
                                        _sortPreference == 'date_added'
                                            ? 'createdAt'
                                            : _sortPreference == 'release_date'
                                                ? 'publishedDate'
                                                : _sortPreference,
                                        descending:
                                            _sortPreference == 'date_added' ||
                                                    _sortPreference ==
                                                        'release_date'
                                                ? true
                                                : false,
                                      )
                                      .snapshots()
                                  : Stream.empty(),
                          builder: (context, snapshot) {
                            print(
                                'StreamBuilder: Connection state: ${snapshot.connectionState}');
                            print(
                                'StreamBuilder: Query type: ${_selectedListName == 'Home' ? 'collectionGroup(books)' : 'users/${user?.uid ?? "no-user"}/lists/$_selectedListId/books'}');
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              print('StreamBuilder: Waiting for data');
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            if (snapshot.hasError) {
                              print('StreamBuilder error: ${snapshot.error}');
                              print('Stack trace: ${snapshot.stackTrace}');
                              print(
                                  'Query: ${_selectedListName == 'Home' ? 'collectionGroup(books)' : 'users/${user?.uid}/lists/$_selectedListId/books'}');
                              String errorMessage =
                                  'Error loading books: ${snapshot.error}';
                              if (snapshot.error
                                  .toString()
                                  .contains('permission-denied')) {
                                errorMessage =
                                    'Permission denied loading books (Error Code: STREAM). Please sign out and sign in again, or contact support if the issue persists.';
                              }
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(errorMessage),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: () async {
                                        if (mounted && user != null) {
                                          print('Retrying StreamBuilder');
                                          print(
                                              'Refreshing auth token before retry');
                                          await user.getIdToken(true);
                                          print(
                                              'Token refreshed for StreamBuilder retry');
                                          setState(() {});
                                        }
                                      },
                                      child: const Text('Retry'),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () async {
                                        if (mounted) {
                                          print(
                                              'Signing out due to StreamBuilder error');
                                          await FirebaseAuth.instance.signOut();
                                        }
                                      },
                                      child: const Text('Sign Out'),
                                    ),
                                  ],
                                ),
                              );
                            }
                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
                              print('StreamBuilder: No books found');
                              return const Center(
                                  child: Text('No books found'));
                            }
                            print(
                                'StreamBuilder: Books found: ${snapshot.data!.docs.length}');
                            print(
                                'StreamBuilder: Document paths: ${snapshot.data!.docs.map((doc) => doc.reference.path).toList()}');

                            List<BookWithList> booksWithList = [];
                            for (var doc in snapshot.data!.docs) {
                              final book = Book.fromMap(
                                  doc.data() as Map<String, dynamic>);
                              String listId;
                              String listName;
                              if (_selectedListName == 'Home') {
                                final pathParts = doc.reference.path.split('/');
                                listId = pathParts[pathParts.length - 3];
                                listName = listNames[listId] ?? 'Unknown List';
                                print(
                                    'Book: ${book.title}, List ID: $listId, List Name: $listName, Path: ${doc.reference.path}');
                              } else {
                                listId = _selectedListId!;
                                listName = _selectedListName;
                              }
                              booksWithList.add(BookWithList(
                                book: book,
                                listId: listId,
                                listName: listName,
                              ));
                            }

                            if (_selectedListName == 'Home') {
                              booksWithList.sort((a, b) {
                                final aBook = a.book;
                                final bBook = b.book;
                                switch (_sortPreference) {
                                  case 'title':
                                    return aBook.title
                                        .toLowerCase()
                                        .compareTo(bBook.title.toLowerCase());
                                  case 'author':
                                    return (aBook.authors?.join(', ') ?? '')
                                        .toLowerCase()
                                        .compareTo(
                                            (bBook.authors?.join(', ') ?? '')
                                                .toLowerCase());
                                  case 'date_added':
                                    return (bBook.dateAdded ?? DateTime.now())
                                        .compareTo(
                                            aBook.dateAdded ?? DateTime.now());
                                  case 'release_date':
                                    return (bBook.releaseDate ?? DateTime.now())
                                        .compareTo(aBook.releaseDate ??
                                            DateTime.now());
                                  default:
                                    return 0;
                                }
                              });
                            }

                            final groupedBooks = <String, List<BookWithList>>{};
                            for (var bookWithList in booksWithList) {
                              groupedBooks
                                  .putIfAbsent(bookWithList.listName, () => [])
                                  .add(bookWithList);
                            }
                            final sortedListNames = groupedBooks.keys.toList()
                              ..sort();

                            final displayItems = <dynamic>[];
                            for (var listName in sortedListNames) {
                              displayItems.add(listName);
                              displayItems.addAll(groupedBooks[listName]!);
                            }

                            return ListView.builder(
                              itemCount: displayItems.length,
                              itemBuilder: (context, index) {
                                final item = displayItems[index];
                                if (item is String) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (index > 0)
                                        const SizedBox(height: 1.0),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16.0, vertical: 8.0),
                                        child: Text(
                                          item,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  );
                                } else if (item is BookWithList) {
                                  final book = item.book;
                                  final isFirstBook = index > 0 &&
                                      displayItems[index - 1] is String;
                                  final isLastBook =
                                      index < displayItems.length - 1 &&
                                          displayItems[index + 1] is String;

                                  return Card(
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(
                                            isFirstBook ? 12 : 0),
                                        topRight: Radius.circular(
                                            isFirstBook ? 12 : 0),
                                        bottomLeft: Radius.circular(
                                            isLastBook ? 12 : 0),
                                        bottomRight: Radius.circular(
                                            isLastBook ? 12 : 0),
                                      ),
                                    ),
                                    margin: EdgeInsets.only(
                                      left: 16.0,
                                      right: 16.0,
                                      top: isFirstBook ? 8.0 : 0,
                                      bottom: isLastBook ? 8.0 : 0,
                                    ),
                                    child: ListTile(
                                      leading: book.imageUrl != null
                                          ? Image.network(
                                              book.imageUrl!,
                                              width: 50,
                                              height: 75,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error,
                                                      stackTrace) =>
                                                  const Icon(Icons.book,
                                                      size: 50),
                                            )
                                          : const Icon(Icons.book, size: 50),
                                      title: Text(book.title),
                                      subtitle: Text(
                                        book.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      onTap: () {
                                        print('Tapped book: ${book.title}');
                                        BookDetailsCard.show(
                                          context,
                                          book,
                                          item.listName,
                                          _bookService,
                                          item.listId,
                                        );
                                      },
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            );
                          },
                        );
                      },
                    ),
      floatingActionButtonLocation: ExpandableFab.location,
      floatingActionButton: ExpandableFab(
        key: _fabKey,
        type: ExpandableFabType.up,
        distance: 60.0,
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
                  context, _selectedListId, _selectedListName, _bookService);
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
            tooltip: 'Scan Barcode',
          ),
        ],
      ),
    );
  }

  Future<Map<String, String>> _fetchListNames(String userId) async {
    if (!mounted) return {};
    print('Fetching list names for user: $userId');
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('lists')
          .get();
      print('List names query completed: ${snapshot.docs.length} lists found');
      final listNames = <String, String>{};
      for (var doc in snapshot.docs) {
        listNames[doc.id] = doc['name'] as String;
      }
      return listNames;
    } catch (e, stackTrace) {
      print('Error fetching list names: $e');
      print('Stack trace: $stackTrace');
      throw Exception('Failed to fetch list names: $e');
    }
  }
}
