import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/book.dart';
import '../services/book_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'select_list_bottom_sheet.dart';

class BookSearchSheet {
  static void show(BuildContext context, String? listId, String listName,
      BookService bookService,
      {VoidCallback? onListCreated}) {
    final TextEditingController controller = TextEditingController();
    List<Book> searchResults = [];
    ScrollController? _scrollController;
    bool _canDismiss = false;

    void _handleScroll() {
      if (_scrollController?.position.pixels == 0) {
        _canDismiss = true;
      } else if (_canDismiss) {
        _canDismiss = false;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            _scrollController = scrollController;
            _scrollController?.addListener(_handleScroll);

            return WillPopScope(
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
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
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
                            'Add Book',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
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
                                  final results =
                                      await bookService.searchBooks(value);
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
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    const Icon(Icons.book,
                                                        size: 50),
                                          )
                                        : const Icon(Icons.book, size: 50),
                                    title: Text(book.title),
                                    subtitle: Text(book.authors?.join(', ') ??
                                        'Unknown Author'),
                                    onTap: () async {
                                      try {
                                        final user =
                                            FirebaseAuth.instance.currentUser!;

                                        if (!context.mounted) return;

                                        // Use the new bottom sheet instead of dialog
                                        final selectedList =
                                            await SelectListBottomSheet.show(
                                          context,
                                          book,
                                          onListCreated: onListCreated,
                                        );

                                        if (selectedList == null) return;

                                        // Navigation is handled by the bottom sheet
                                        // The book is already added to the selected list
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    'Error adding book: $e')),
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
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
