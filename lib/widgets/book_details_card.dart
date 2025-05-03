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

  const BookDetailsCard({
    super.key,
    required this.book,
    required this.listName,
    required this.bookService,
    this.listId,
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
  bool _isDescriptionExpanded = false;
  double _userRating = 0;

  @override
  void initState() {
    super.initState();
    _userRating = widget.book.userRating ?? 0;
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
      maxChildSize: 0.9,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 26.0, 16.0, 16.0),
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
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          if (widget.book.authors != null &&
                              widget.book.authors!.isNotEmpty)
                            Text(
                              widget.book.authors!.join(', '),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          if (widget.book.publisher != null)
                            Text(
                              'Published by ${widget.book.publisher}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (widget.book.publishedDate != null)
                            Text(
                              'Published: ${widget.book.publishedDate}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          if (widget.book.pageCount != null)
                            Text(
                              '${widget.book.pageCount} pages',
                              style: Theme.of(context).textTheme.bodySmall,
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
                            _isDescriptionExpanded = !_isDescriptionExpanded;
                          });
                        },
                        child: Text(
                            _isDescriptionExpanded ? 'Show Less' : 'Show More'),
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
                          index < _userRating ? Icons.star : Icons.star_border,
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
        );
      },
    );
  }
}
