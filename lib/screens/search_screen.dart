import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../models/book.dart';
import '../services/book_service.dart';
import 'dart:async';
import '../screens/user_page.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Book> _searchResults = [];
  List<Map<String, dynamic>> _peopleResults = [];
  bool _isLoading = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _searchBooks(String query) async {
    if (query.isEmpty) {
      if (_searchResults.isNotEmpty) {
        setState(() {
          _searchResults = [];
        });
      }
      return;
    }

    // Cancel any existing timer
    _debounceTimer?.cancel();

    // Set a new timer
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        // Search in all books across all lists
        final snapshot = await FirebaseFirestore.instance
            .collectionGroup('books')
            .where('userId', isEqualTo: user.uid)
            .get();

        // Filter books by title (case-insensitive)
        final newResults = snapshot.docs.where((doc) {
          final data = doc.data();
          final title = data['title']?.toString().toLowerCase() ?? '';
          return title.contains(query.toLowerCase());
        }).map((doc) {
          final data = doc.data();
          return Book(
            title: data['title'] ?? '',
            authors: List<String>.from(data['authors'] ?? []),
            isbn: data['isbn'] ?? '',
            imageUrl: data['imageUrl'],
            description: data['description'],
            publisher: data['publisher'],
            publishedDate: data['publishedDate'],
            pageCount: data['pageCount'],
            categories: List<String>.from(data['categories'] ?? []),
          );
        }).toList();

        // Only update state if the results have changed
        if (!_areListsEqual(_searchResults, newResults)) {
          if (mounted) {
            setState(() {
              _searchResults = newResults;
              _isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error searching books: $e')),
          );
        }
      }
    });
  }

  bool _areListsEqual(List<Book> list1, List<Book> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].isbn != list2[i].isbn) return false;
    }
    return true;
  }

  Future<void> _searchPeople(String query) async {
    if (query.isEmpty) {
      if (_peopleResults.isNotEmpty) {
        setState(() {
          _peopleResults = [];
        });
      }
      return;
    }

    // Cancel any existing timer
    _debounceTimer?.cancel();

    // Set a new timer
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      setState(() {
        _isLoading = true;
      });

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        // Search for users by username
        final snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isGreaterThanOrEqualTo: query.toLowerCase())
            .where('username',
                isLessThanOrEqualTo: query.toLowerCase() + '\uf8ff')
            .limit(20)
            .get();

        final newResults = snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            'uid': doc.id,
            'username': data['username'] ?? 'Unknown User',
            'bio': data['bio'] ?? '',
            'profileImage': data['profileImageBase64'],
            'displayName': data['displayName'] ?? '',
            'email': data['email'] ?? '',
          };
        }).toList();

        // Only update state if the results have changed
        if (!_arePeopleListsEqual(_peopleResults, newResults)) {
          if (mounted) {
            setState(() {
              _peopleResults = newResults;
              _isLoading = false;
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error searching people: $e')),
          );
        }
      }
    });
  }

  bool _arePeopleListsEqual(
      List<Map<String, dynamic>> list1, List<Map<String, dynamic>> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i]['uid'] != list2[i]['uid']) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Theme.of(context).hintColor),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
            if (_tabController.index == 0) {
              _searchBooks(value);
            } else {
              _searchPeople(value);
            }
          },
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Books'),
            Tab(text: 'People'),
          ],
          onTap: (index) {
            if (_searchQuery.isNotEmpty) {
              if (index == 0) {
                _searchBooks(_searchQuery);
              } else {
                _searchPeople(_searchQuery);
              }
            }
          },
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Books Tab
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _searchResults.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'Search for books...'
                            : 'No books found',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _searchResults.length,
                      itemBuilder: (context, index) {
                        final book = _searchResults[index];
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
                          subtitle: Text(book.authors?.join(', ') ?? ''),
                          onTap: () {
                            // TODO: Show book details
                          },
                        );
                      },
                    ),

          // People Tab
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _peopleResults.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'Search for people...'
                            : 'No people found',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _peopleResults.length,
                      itemBuilder: (context, index) {
                        final person = _peopleResults[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: person['profileImage'] != null
                                ? MemoryImage(
                                    base64Decode(person['profileImage']))
                                : null,
                            child: person['profileImage'] == null
                                ? const Icon(Icons.person)
                                : null,
                          ),
                          title: Text('@${person['username']}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (person['displayName']?.isNotEmpty ?? false)
                                Text(person['displayName']),
                              if (person['bio']?.isNotEmpty ?? false)
                                Text(
                                  person['bio'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => UserPage(
                                  userId: person['uid'],
                                  username: person['username'],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
        ],
      ),
    );
  }
}
