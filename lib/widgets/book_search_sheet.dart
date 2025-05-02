import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/book.dart';
import '../services/book_service.dart';

class BookSearchSheet {
  static void show(
    BuildContext context,
    String? listId,
    String listName,
    BookService bookService,
  ) {
    final TextEditingController controller = TextEditingController();
    List<Book> searchResults = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.5,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'Search by Title or ISBN',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) async {
                    if (value.length > 2) {
                      final results = await bookService.searchBooks(value);
                      setState(() {
                        searchResults = results;
                      });
                    } else {
                      setState(() {
                        searchResults = [];
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: searchResults.length,
                    itemBuilder: (context, index) {
                      final book = searchResults[index];
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
                        subtitle: Text(book.authors?.join(', ') ?? 'Unknown Author'),
                        onTap: () async {
                          try {
                            final user = FirebaseAuth.instance.currentUser!;
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(user.uid)
                                .collection('lists')
                                .doc(listId)
                                .collection('books')
                                .doc(book.isbn)
                                .set({
                              ...book.toMap(),
                              'userId': user.uid, // Add userId for security rules
                              'createdAt': FieldValue.serverTimestamp(),
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Added "${book.title}" to $listName'),
                                ),
                              );
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error adding book: $e')),
                              );
                            }
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}