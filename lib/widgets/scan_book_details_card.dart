import 'package:flutter/material.dart';
import '../models/book.dart';
import '../services/book_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ScanBookDetailsCard extends StatefulWidget {
  final Book book;
  final BookService bookService;
  final Map<String, String> lists;

  const ScanBookDetailsCard({
    super.key,
    required this.book,
    required this.bookService,
    required this.lists,
  });

  @override
  _ScanBookDetailsCardState createState() => _ScanBookDetailsCardState();
}

class _ScanBookDetailsCardState extends State<ScanBookDetailsCard> {
  String? _selectedListId;
  String? _selectedListName;

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
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving book: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Container(
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.book.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
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
                controller: scrollController,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.book.imageUrl != null)
                        Center(
                          child: Image.network(
                            widget.book.imageUrl!,
                            height: 200,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.book, size: 200),
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (widget.book.description != null)
                        Text(
                          widget.book.description!,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      const SizedBox(height: 16),
                      if (widget.book.publisher != null)
                        Text('Publisher: ${widget.book.publisher}'),
                      if (widget.book.publishedDate != null)
                        Text('Published: ${widget.book.publishedDate}'),
                      if (widget.book.pageCount != null)
                        Text('Pages: ${widget.book.pageCount}'),
                      const SizedBox(height: 16),
                      Text('ISBN: ${widget.book.isbn}'),
                      const SizedBox(height: 16),
                      if (_selectedListName != null)
                        Text('Selected List: $_selectedListName'),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _showListSelectionDialog,
                      child: const Text('Select List'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveBook,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
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
    );
  }
}
