import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/book.dart';
import '../services/book_service.dart';

class BookSearchSheet {
  static void show(BuildContext context, String? selectedListId, String selectedListName, BookService bookService) {
    if (selectedListId == null) {
      print('No list selected for search');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or create a list first')),
      );
      return;
    }

    final TextEditingController controller = TextEditingController();
    List<Book> searchResults = [];
    bool isSearching = false;
    String? selectedIsbn;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) => StatefulBuilder(
        builder: (modalContext, setModalState) => Container(
          height: MediaQuery.of(modalContext).size.height * 0.9,
          decoration: BoxDecoration(
            color: Theme.of(modalContext).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Search Books',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'Enter book title or ISBN',
                    suffixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) async {
                    print('Search input changed: $value');
                    setModalState(() {
                      isSearching = true;
                      selectedIsbn = null;
                    });
                    final results = await bookService.searchBooks(value);
                    if (modalContext.mounted) {
                      setModalState(() {
                        searchResults = results;
                        isSearching = false;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: isSearching
                      ? const Center(child: CircularProgressIndicator())
                      : searchResults.isEmpty
                          ? const Center(child: Text('No results found'))
                          : ListView.builder(
                              itemCount: searchResults.length,
                              itemBuilder: (context, index) {
                                final book = searchResults[index];
                                final isAdding = selectedIsbn == book.isbn;
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
                                    book.authors?.join(', ') ?? 'Unknown',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: isAdding
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : null,
                                  onTap: isAdding
                                      ? null
                                      : () async {
                                          if (book.isbn.isEmpty) {
                                            print('Invalid book: No ISBN for ${book.title}');
                                            ScaffoldMessenger.of(modalContext).showSnackBar(
                                              const SnackBar(
                                                content: Text('Invalid book: No ISBN available'),
                                              ),
                                            );
                                            return;
                                          }
                                          print('Selected book: ${book.title}, ISBN: ${book.isbn}');
                                          setModalState(() {
                                            selectedIsbn = book.isbn;
                                          });
                                          print('Adding book to Firestore: ${book.title}');
                                          try {
                                            final docRef = FirebaseFirestore.instance
                                                .collection('users')
                                                .doc(FirebaseAuth.instance.currentUser!.uid)
                                                .collection('lists')
                                                .doc(selectedListId)
                                                .collection('books')
                                                .doc(book.isbn);
                                            print('Writing to Firestore at: ${docRef.path}');
                                            await docRef.set(book.toMap());
                                            print('Book added successfully: ${book.title}');
                                            if (modalContext.mounted) {
                                              ScaffoldMessenger.of(modalContext).showSnackBar(
                                                SnackBar(
                                                  content: Text('Book added to $selectedListName: ${book.title}'),
                                                ),
                                              );
                                            }
                                          } catch (e, stackTrace) {
                                            print('Error adding book: $e');
                                            print('Stack trace: $stackTrace');
                                            if (modalContext.mounted) {
                                              ScaffoldMessenger.of(modalContext).showSnackBar(
                                                SnackBar(content: Text('Error adding book: $e')),
                                              );
                                            }
                                          } finally {
                                            print('Entering finally block for book add');
                                            if (modalContext.mounted) {
                                              setModalState(() {
                                                selectedIsbn = null;
                                                print('Reset selectedIsbn');
                                              });
                                              print('Scheduling modal dismissal');
                                              await Future.delayed(const Duration(milliseconds: 100));
                                              if (modalContext.mounted) {
                                                print('Dismissing search sheet');
                                                Navigator.of(modalContext).pop();
                                              } else {
                                                print('Modal context not mounted, cannot pop');
                                              }
                                            } else {
                                              print('Modal context not mounted in finally block');
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