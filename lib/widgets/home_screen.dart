import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/book.dart';
import '../services/book_service.dart';
import 'book_search_sheet.dart';
import 'book_details_card.dart';

class HomeScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;

  const HomeScreen({super.key, required this.onThemeChanged});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _selectedListId;
  String _selectedListName = 'myBookNook';
  final _fabKey = GlobalKey<ExpandableFabState>();
  String? _errorMessage;
  bool _isLoading = true;
  late BookService _bookService;

  @override
  void initState() {
    super.initState();
    _bookService = BookService(context);
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);
    print('HomeScreen initState: Waiting for auth state');
    FirebaseAuth.instance.authStateChanges().firstWhere((user) => user != null).then((user) {
      print('HomeScreen initState: User authenticated: ${user?.uid}, email: ${user?.email}');
      _initializeDefaultList();
    }).catchError((e, stackTrace) {
      print('HomeScreen initState: Error waiting for auth state: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Authentication error: $e. Please sign in again.';
        _isLoading = false;
      });
    });
  }

  Future<void> _initializeDefaultList() async {
    print('Initializing default list');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('No authenticated user found');
      setState(() {
        _errorMessage = 'No authenticated user. Please sign in again.';
        _isLoading = false;
      });
      return;
    }
    print('Authenticated user: UID=${user.uid}, email=${user.email}');
    try {
      print('Forcing authentication token refresh');
      await user.getIdToken(true);
      print('Token refreshed successfully');

      print('Creating user document at /users/${user.uid}');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({'createdAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      print('User document created or updated successfully');

      print('Checking if lists collection exists at /users/${user.uid}/lists');
      final listsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .limit(1)
          .get();
      print('Lists collection query result: ${listsSnapshot.docs.length} documents found');

      print('Querying for myBookNook list at /users/${user.uid}/lists');
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .where('name', isEqualTo: 'myBookNook')
          .limit(1)
          .get();
      print('myBookNook query completed: ${snapshot.docs.length} list(s) found');
      if (snapshot.docs.isEmpty) {
        print('No myBookNook list found, creating new list');
        final listRef = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('lists')
            .add({
          'name': 'myBookNook',
          'createdAt': FieldValue.serverTimestamp(),
        });
        print('Created default list with ID: ${listRef.id}');
        setState(() {
          _selectedListId = listRef.id;
          _selectedListName = 'myBookNook';
        });
      } else {
        print('Found existing default list with ID: ${snapshot.docs.first.id}');
        setState(() {
          _selectedListId = snapshot.docs.first.id;
          _selectedListName = 'myBookNook';
        });
      }
      if (_selectedListId == null) {
        print('Error: _selectedListId is still null after initialization');
        throw Exception('Failed to initialize default list ID');
      }
      print('Initialization complete: _selectedListId=$_selectedListId, _selectedListName=$_selectedListName');
    } catch (e, stackTrace) {
      print('Error initializing default list: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _errorMessage = 'Failed to load lists: $e';
        if (e.toString().contains('permission-denied')) {
          _errorMessage = 'Permission denied accessing lists. Please sign out and sign in again.';
        }
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      print('Initialization finished, _isLoading=false');
    }
  }

  Future<void> _addNewList() async {
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

    if (newListName != null) {
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
        setState(() {
          _selectedListId = listRef.id;
          _selectedListName = newListName;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('List "$newListName" created')),
        );
      } catch (e, stackTrace) {
        print('Error creating new list: $e');
        print('Stack trace: $stackTrace');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating list: $e')),
        );
      }
    }
  }

  Future<void> _deleteList(String listId, String listName) async {
    print('Attempting to delete list: $listName (ID: $listId)');
    if (listName == 'myBookNook') {
      print('Cannot delete default list');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot delete the default "myBookNook" list')),
      );
      return;
    }

    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete List'),
        content: Text('Are you sure you want to delete "$listName" and all its books?'),
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

    if (confirmDelete == true) {
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
        if (_selectedListId == listId) {
          print('Selected list deleted, reinitializing default list');
          await _initializeDefaultList();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('List "$listName" deleted')),
        );
      } catch (e, stackTrace) {
        print('Error deleting list: $e');
        print('Stack trace: $stackTrace');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting list: $e')),
        );
      }
    }
  }

  Future<void> scanBarcode() async {
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission denied')),
        );
        return;
      }

      var result = await BarcodeScanner.scan();
      String isbn = result.rawContent;
      print('Scanned ISBN: $isbn');

      if (isbn.isNotEmpty) {
        Book? book = await _bookService.fetchBookDetails(isbn);
        if (book != null) {
          print('Book found: ${book.title}');
          await FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser!.uid)
              .collection('lists')
              .doc(_selectedListId)
              .collection('books')
              .doc(isbn)
              .set(book.toMap());
          print('Book added via barcode: ${book.title}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Book added to $_selectedListName: ${book.title}')),
          );
        } else {
          print('Book not found for ISBN: $isbn');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Book not found')),
          );
        }
      } else {
        print('No ISBN scanned');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No ISBN detected')),
        );
      }
    } catch (e, stackTrace) {
      print('Error during barcode scan: $e');
      print('Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error scanning barcode: $e')),
      );
    }
  }

  List<PopupMenuEntry<String>> _buildListMenuItems() {
    print('Building list menu items');
    return [
      PopupMenuItem<String>(
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser!.uid)
              .collection('lists')
              .orderBy('createdAt')
              .snapshots(),
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
                errorMessage = 'Permission denied loading lists. Please sign out and sign in again.';
              }
              return ListTile(
                title: Text(errorMessage),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    print('Retrying list menu load');
                    setState(() {}); // Trigger rebuild
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
                    setState(() {
                      _selectedListId = listId;
                      _selectedListName = listName;
                    });
                  },
                  child: ListTile(
                    title: Text(listName),
                    trailing: listName == 'myBookNook'
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
    print('Building HomeScreen for user: ${user?.email ?? "No user"}');
    return Scaffold(
      appBar: AppBar(
        title: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'add_list') {
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
              if (value == 'sign_out') {
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
                        onPressed: _initializeDefaultList,
                        child: const Text('Retry'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          print('Signing out due to error');
                          FirebaseAuth.instance.signOut();
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
                            onPressed: _initializeDefaultList,
                            child: const Text('Retry'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              print('Signing out due to null list ID');
                              FirebaseAuth.instance.signOut();
                            },
                            child: const Text('Sign Out'),
                          ),
                        ],
                      ),
                    )
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(user!.uid)
                          .collection('lists')
                          .doc(_selectedListId)
                          .collection('books')
                          .snapshots(),
                      builder: (context, snapshot) {
                        print('StreamBuilder: Connection state: ${snapshot.connectionState}');
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          print('StreamBuilder: Waiting for data');
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          print('StreamBuilder error: ${snapshot.error}');
                          print('Stack trace: ${snapshot.stackTrace}');
                          String errorMessage = 'Error loading books: ${snapshot.error}';
                          if (snapshot.error.toString().contains('permission-denied')) {
                            errorMessage = 'Permission denied loading books. Please sign out and sign in again.';
                          }
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(errorMessage),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: () {
                                    print('Retrying StreamBuilder');
                                    setState(() {});
                                  },
                                  child: const Text('Retry'),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () {
                                    print('Signing out due to StreamBuilder error');
                                    FirebaseAuth.instance.signOut();
                                  },
                                  child: const Text('Sign Out'),
                                ),
                              ],
                            ),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          print('StreamBuilder: No books found');
                          return const Center(child: Text('No books found'));
                        }
                        print('StreamBuilder: Books found: ${snapshot.data!.docs.length}');
                        final books = snapshot.data!.docs
                            .map((doc) => Book.fromMap(doc.data() as Map<String, dynamic>))
                            .toList();
                        return ListView.builder(
                          itemCount: books.length,
                          itemBuilder: (context, index) {
                            final book = books[index];
                            return ListTile(
                              leading: book.imageUrl != null
                                  ? Image.network(
                                      book.imageUrl!,
                                      width: 50,
                                      height: 75,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const Icon(Icons.book, size: 50),
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
                                  _selectedListName,
                                  _bookService,
                                  _selectedListId,
                                );
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
          backgroundColor: const Color(0xFFE8F5E9), // Pale green
          shape: const CircleBorder(),
        ),
        closeButtonBuilder: DefaultFloatingActionButtonBuilder(
          child: const Icon(Icons.close),
          foregroundColor: Colors.white,
          backgroundColor: const Color(0xFFE8F5E9), // Pale green
          shape: const CircleBorder(),
        ),
        children: [
          FloatingActionButton.small(
            heroTag: 'search_fab',
            backgroundColor: const Color(0xFFC8E6C9), // Darker green
            foregroundColor: Colors.white,
            onPressed: () {
              print('Search FAB pressed');
              final state = _fabKey.currentState;
              if (state != null && state.isOpen) {
                print('Toggling FAB closed');
                state.toggle();
              }
              BookSearchSheet.show(context, _selectedListId, _selectedListName, _bookService);
            },
            child: const Icon(Icons.search),
            tooltip: 'Search by Title or ISBN',
          ),
          FloatingActionButton.small(
            heroTag: 'scan_fab',
            backgroundColor: const Color(0xFFC8E6C9), // Darker green
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
}