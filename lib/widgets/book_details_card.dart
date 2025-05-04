import 'package:flutter/material.dart';
import '../models/book.dart';
import '../services/book_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BookDetailsCard extends StatefulWidget {
  final Book book;
  final String listName;
  final BookService bookService;
  final String? listId;
  final Function(String)? onAddToList;
  final Map<String, String>? lists;

  const BookDetailsCard({
    super.key,
    required this.book,
    required this.listName,
    required this.bookService,
    this.listId,
    this.onAddToList,
    this.lists,
  });

  static void show(BuildContext context, Book book, String listName,
      BookService bookService, String? listId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return BookDetailsCard(
          book: book,
          listName: listName,
          bookService: bookService,
          listId: listId,
        );
      },
    );
  }

  @override
  State<BookDetailsCard> createState() => _BookDetailsCardState();
}

class _BookDetailsCardState extends State<BookDetailsCard> {
  final ScrollController scrollController = ScrollController();
  bool _isExpanded = false;
  double _userRating = 0;
  bool _isDescriptionExpanded = false;
  ScrollController? _scrollController;
  bool _canDismiss = false;

  @override
  void initState() {
    super.initState();
    _userRating = widget.book.userRating ?? 0;
    _scrollController = ScrollController();
    _scrollController?.addListener(_handleScroll);
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    _scrollController?.removeListener(_handleScroll);
    _scrollController?.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (scrollController.position.pixels <= 0) {
      // Allow dismissal when at the top
      Navigator.of(context).pop();
    }
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

  Future<void> _updateReadingStatus(BuildContext context, bool isRead) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final bookRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .doc(widget.listId)
          .collection('books')
          .doc(widget.book.isbn);

      await bookRef.update({
        'isRead': isRead,
        'currentPage': isRead ? widget.book.pageCount : 0,
        if (isRead) 'finishedReading': FieldValue.serverTimestamp(),
        if (!isRead) 'finishedReading': null,
      });

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

  Future<void> _updateUserRating(BuildContext context, double rating) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final bookRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .doc(widget.listId)
          .collection('books')
          .doc(widget.book.isbn);

      await bookRef.update({
        'userRating': rating,
      });

      setState(() {
        _userRating = rating;
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rating updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating rating: $e')),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          widget.book.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    if (widget.book.authors != null &&
                        widget.book.authors!.isNotEmpty)
                      Text(
                        widget.book.authors!.join(', '),
                        style: Theme.of(context).textTheme.titleMedium,
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
                                  Text(
                                    widget.book.title,
                                    style:
                                        Theme.of(context).textTheme.titleLarge,
                                  ),
                                  if (widget.book.authors != null &&
                                      widget.book.authors!.isNotEmpty)
                                    Text(
                                      widget.book.authors!.join(', '),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
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
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
