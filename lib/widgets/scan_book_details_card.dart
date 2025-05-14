import 'package:flutter/material.dart';
import '../models/book.dart';
import '../services/book_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings.dart' as app_settings;
import 'dart:convert';
import 'select_list.dart' show SelectListDialog;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'author_details_card.dart';

class ScanBookDetailsCard extends StatefulWidget {
  final Book book;
  final BookService bookService;
  final Map<String, String> lists;
  final VoidCallback? onClose;

  const ScanBookDetailsCard({
    super.key,
    required this.book,
    required this.bookService,
    required this.lists,
    this.onClose,
  });

  @override
  _ScanBookDetailsCardState createState() => _ScanBookDetailsCardState();
}

class _ScanBookDetailsCardState extends State<ScanBookDetailsCard> {
  String? _selectedListId;
  String? _selectedListName;
  bool _isDescriptionExpanded = false;
  ScrollController? _scrollController;
  bool _canDismiss = false;
  double _userRating = 0.0;
  bool _isRead = false;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController?.addListener(_handleScroll);
    _loadReadingStatus();
    _loadFavoriteStatus();
  }

  @override
  void dispose() {
    _scrollController?.removeListener(_handleScroll);
    _scrollController?.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController?.position.pixels == 0) {
      setState(() {
        _canDismiss = true;
      });
    } else if (_canDismiss) {
      setState(() {
        _canDismiss = false;
      });
    }
  }

  void _handleClose() {
    if (widget.onClose != null) {
      widget.onClose!();
    }
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showListSelectionDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final listsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .where('name', isNotEqualTo: 'Home')
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
          title: const Text('Select List'),
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
        setState(() {
          _selectedListId = selectedList['id'];
          _selectedListName = selectedList['name'];
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading lists: $e')),
      );
    }
  }

  Future<void> _saveBook() async {
    if (_selectedListId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a list first')),
      );
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .doc(_selectedListId)
          .collection('books')
          .doc(widget.book.isbn)
          .set({
        'title': widget.book.title,
        'authors': widget.book.authors,
        'description': widget.book.description,
        'imageUrl': widget.book.imageUrl,
        'isbn': widget.book.isbn,
        'publishedDate': widget.book.publishedDate,
        'publisher': widget.book.publisher,
        'pageCount': widget.book.pageCount,
        'categories': widget.book.categories,
        'tags': widget.book.tags,
        'userId': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Book saved to $_selectedListName')),
      );
      _handleClose();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving book: $e')),
      );
    }
  }

  Future<void> _updateReadingStatus(BuildContext context, bool isRead) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completedBooksKey = 'completed_books';
      final completedBooks = prefs.getStringList(completedBooksKey) ?? [];

      if (isRead) {
        if (!completedBooks.contains(widget.book.isbn)) {
          completedBooks.add(widget.book.isbn);
          await prefs.setStringList(completedBooksKey, completedBooks);

          // Update reading statistics
          final settings = app_settings.Settings();
          await settings.load();
          await settings.incrementReadBooks();
          await settings.save();
        }
      } else {
        if (completedBooks.contains(widget.book.isbn)) {
          completedBooks.remove(widget.book.isbn);
          await prefs.setStringList(completedBooksKey, completedBooks);

          // Update reading statistics
          final settings = app_settings.Settings();
          await settings.load();
          await settings.decrementReadBooks();
          await settings.save();
        }
      }

      // Update the state immediately
      if (mounted) {
        setState(() {
          widget.book.isRead = isRead;
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reading status updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e')),
        );
      }
    }
  }

  void _updateUserRating(BuildContext context, double rating) {
    setState(() {
      _userRating = rating;
    });
  }

  Future<void> _loadReadingStatus() async {
    final isCompleted = await Book.isBookCompleted(widget.book.isbn);
    if (mounted) {
      setState(() {
        widget.book.isRead = isCompleted;
      });
    }
  }

  Future<void> _loadFavoriteStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final favoriteBooksJson = prefs.getString('favoriteBooks') ?? '[]';
    final List<dynamic> favoriteBooksList = jsonDecode(favoriteBooksJson);
    final isFavorite =
        favoriteBooksList.any((book) => book['isbn'] == widget.book.isbn);
    if (mounted) {
      setState(() {
        _isFavorite = isFavorite;
      });
    }
  }

  Future<void> _toggleFavorite() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_selectedListId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a list first')),
      );
      return;
    }

    try {
      // Update Firebase
      final bookRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('books')
          .doc(widget.book.isbn);

      if (_isFavorite) {
        // Remove from favorites in Firebase
        await bookRef.update({
          'isFavorite': false,
          'listId': null,
        });
      } else {
        // Add to favorites in Firebase
        await bookRef.set({
          ...widget.book.toMap(),
          'isFavorite': true,
          'listId': _selectedListId,
        }, SetOptions(merge: true));
      }

      // Update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final favoriteBooksJson = prefs.getString('favoriteBooks') ?? '[]';
      final List<dynamic> favoriteBooksList = jsonDecode(favoriteBooksJson);

      if (_isFavorite) {
        // Remove from favorites
        favoriteBooksList
            .removeWhere((book) => book['isbn'] == widget.book.isbn);
      } else {
        // Add to favorites
        favoriteBooksList.add({
          'title': widget.book.title,
          'authors': widget.book.authors,
          'imageUrl': widget.book.imageUrl,
          'isbn': widget.book.isbn,
          'listId': _selectedListId,
        });
      }

      await prefs.setString('favoriteBooks', jsonEncode(favoriteBooksList));

      if (mounted) {
        setState(() {
          _isFavorite = !_isFavorite;
        });
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                _isFavorite ? 'Removed from favorites' : 'Added to favorites'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating favorite status: $e')),
        );
      }
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch URL')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      snap: true,
      snapSizes: const [0.5, 0.7, 0.9, 0.95],
      builder: (context, scrollController) => WillPopScope(
        onWillPop: () async {
          if (_scrollController?.position.pixels != 0) {
            _scrollController?.animateTo(
              0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
            return false;
          }
          return true;
        },
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      'Book Details',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.book.imageUrl != null)
                              Image.network(
                                widget.book.imageUrl!,
                                width: 120,
                                height: 180,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.book, size: 120),
                              )
                            else
                              const Icon(Icons.book, size: 120),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          widget.book.title,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (widget.book.authors != null &&
                                      widget.book.authors!.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          builder: (BuildContext context) {
                                            return AuthorDetailsCard(
                                              authorName:
                                                  widget.book.authors!.first,
                                            );
                                          },
                                        );
                                      },
                                      child: Text(
                                        widget.book.authors!.join(', '),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                      ),
                                    ),
                                  if (widget.book.publisher != null)
                                    Text(
                                      'Published by ${widget.book.publisher}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  if (widget.book.publishedDate != null)
                                    Text(
                                      'Published: ${widget.book.publishedDate}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  if (widget.book.pageCount != null)
                                    Text(
                                      '${widget.book.pageCount} pages',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (widget.book.description != null) ...[
                          Text(
                            'Description',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.book.description!,
                                maxLines: _isDescriptionExpanded ? null : 5,
                                overflow: _isDescriptionExpanded
                                    ? null
                                    : TextOverflow.ellipsis,
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isDescriptionExpanded =
                                        !_isDescriptionExpanded;
                                  });
                                },
                                child: Text(_isDescriptionExpanded
                                    ? 'Show Less'
                                    : 'Show More'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Your Rating',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ...List.generate(5, (index) {
                              return IconButton(
                                icon: Icon(
                                  index < _userRating
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                onPressed: () {
                                  _updateUserRating(context, index + 1.0);
                                },
                              );
                            }),
                            const SizedBox(width: 8),
                            Text('${_userRating.toInt()}/5'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (widget.book.categories != null &&
                            widget.book.categories!.isNotEmpty) ...[
                          Text(
                            'Categories',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: widget.book.categories!
                                .map((category) => Chip(label: Text(category)))
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (widget.book.tags != null &&
                            widget.book.tags!.isNotEmpty) ...[
                          Text(
                            'Tags',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: widget.book.tags!
                                .map((tag) => Chip(label: Text(tag)))
                                .toList(),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          'Reading Status',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          title: const Text('Mark as read'),
                          value: widget.book.isRead,
                          onChanged: (value) {
                            if (value != null) {
                              _updateReadingStatus(context, value);
                            }
                          },
                        ),
                        ListTile(
                          title: const Text('Mark as favorite'),
                          trailing: IconButton(
                            icon: Icon(
                              _isFavorite ? Icons.star : Icons.star_border,
                              color: _isFavorite ? Colors.amber : null,
                            ),
                            onPressed: _toggleFavorite,
                          ),
                          onTap: _toggleFavorite,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Purchase Book',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: 98,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        final url =
                                            'https://books.google.com/books?isbn=${widget.book.isbn}';
                                        _launchUrl(url);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: SvgPicture.asset(
                                        'assets/logos/google_books.svg',
                                        height: 24,
                                        width: 24,
                                        fit: BoxFit.contain,
                                        placeholderBuilder: (context) =>
                                            const Icon(Icons.book, size: 24),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Google Books',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: 98,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        final url =
                                            'https://www.amazon.com/s?k=${widget.book.isbn}';
                                        _launchUrl(url);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: SvgPicture.asset(
                                          'assets/logos/amazon.svg',
                                          height: 19.2,
                                          width: 19.2,
                                          fit: BoxFit.contain,
                                          placeholderBuilder: (context) =>
                                              const Icon(Icons.shopping_cart,
                                                  size: 19.2),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Amazon',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: 98,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        final url =
                                            'https://www.abebooks.com/servlet/SearchResults?isbn=${widget.book.isbn}';
                                        _launchUrl(url);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer,
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: SvgPicture.asset(
                                        'assets/logos/abebooks.svg',
                                        height: 24,
                                        width: 24,
                                        fit: BoxFit.contain,
                                        placeholderBuilder: (context) =>
                                            const Icon(Icons.store, size: 24),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'AbeBooks',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 26),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final selectedList =
                              await SelectListDialog.show(context, widget.book);
                          if (selectedList != null) {
                            _handleClose();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: Text(_selectedListName ?? 'Select List'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saveBook,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
