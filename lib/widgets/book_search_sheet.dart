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

                                        // Show list selection dialog
                                        final listsSnapshot =
                                            await FirebaseFirestore.instance
                                                .collection('users')
                                                .doc(user.uid)
                                                .collection('lists')
                                                .where('name',
                                                    isNotEqualTo: 'Home')
                                                .get();

                                        final lists =
                                            listsSnapshot.docs.map((doc) {
                                          final data = doc.data();
                                          return {
                                            'id': doc.id,
                                            'name': data['name'] as String? ??
                                                'Unknown List',
                                          };
                                        }).toList();

                                        if (!context.mounted) return;

                                        final selectedList = await showDialog<
                                            Map<String, String>>(
                                          context: context,
                                          builder:
                                              (BuildContext dialogContext) =>
                                                  AlertDialog(
                                            title: const Text('Select List'),
                                            content: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10),
                                              child: SizedBox(
                                                width: double.maxFinite,
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    ListView.builder(
                                                      shrinkWrap: true,
                                                      physics:
                                                          const NeverScrollableScrollPhysics(),
                                                      itemCount: lists.length,
                                                      itemBuilder:
                                                          (context, index) {
                                                        final list =
                                                            lists[index];
                                                        return Card(
                                                          margin:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 4),
                                                          child: InkWell(
                                                            onTap: () =>
                                                                Navigator.pop(
                                                                    dialogContext,
                                                                    list),
                                                            child: Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .all(
                                                                      16.0),
                                                              child: Text(
                                                                list['name']!,
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .titleMedium,
                                                              ),
                                                            ),
                                                          ),
                                                        );
                                                      },
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Padding(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          vertical: 4),
                                                      child: InkWell(
                                                        onTap: () async {
                                                          Navigator.pop(
                                                              dialogContext);
                                                          final newListName =
                                                              await showDialog<
                                                                  String>(
                                                            context: context,
                                                            builder: (BuildContext
                                                                newListContext) {
                                                              final TextEditingController
                                                                  textController =
                                                                  TextEditingController();
                                                              return AlertDialog(
                                                                title: const Text(
                                                                    'New List'),
                                                                content:
                                                                    TextField(
                                                                  controller:
                                                                      textController,
                                                                  autofocus:
                                                                      true,
                                                                  decoration:
                                                                      const InputDecoration(
                                                                    labelText:
                                                                        'List Name',
                                                                    border:
                                                                        OutlineInputBorder(),
                                                                  ),
                                                                  onSubmitted:
                                                                      (value) {
                                                                    if (value
                                                                        .trim()
                                                                        .isNotEmpty) {
                                                                      Navigator.pop(
                                                                          newListContext,
                                                                          value
                                                                              .trim());
                                                                    }
                                                                  },
                                                                ),
                                                                actions: [
                                                                  TextButton(
                                                                    onPressed: () =>
                                                                        Navigator.pop(
                                                                            newListContext),
                                                                    child: const Text(
                                                                        'Cancel'),
                                                                  ),
                                                                  TextButton(
                                                                    onPressed:
                                                                        () {
                                                                      final value = textController
                                                                          .text
                                                                          .trim();
                                                                      if (value
                                                                          .isNotEmpty) {
                                                                        Navigator.pop(
                                                                            newListContext,
                                                                            value);
                                                                      }
                                                                    },
                                                                    child: const Text(
                                                                        'Create'),
                                                                  ),
                                                                ],
                                                              );
                                                            },
                                                          );

                                                          if (newListName !=
                                                                  null &&
                                                              newListName
                                                                  .isNotEmpty) {
                                                            try {
                                                              final user =
                                                                  FirebaseAuth
                                                                      .instance
                                                                      .currentUser!;
                                                              final newListRef =
                                                                  await FirebaseFirestore
                                                                      .instance
                                                                      .collection(
                                                                          'users')
                                                                      .doc(user
                                                                          .uid)
                                                                      .collection(
                                                                          'lists')
                                                                      .add({
                                                                'name':
                                                                    newListName,
                                                                'createdAt':
                                                                    FieldValue
                                                                        .serverTimestamp(),
                                                              });

                                                              // Add the book to the new list
                                                              await FirebaseFirestore
                                                                  .instance
                                                                  .collection(
                                                                      'users')
                                                                  .doc(user.uid)
                                                                  .collection(
                                                                      'lists')
                                                                  .doc(
                                                                      newListRef
                                                                          .id)
                                                                  .collection(
                                                                      'books')
                                                                  .doc(
                                                                      book.isbn)
                                                                  .set({
                                                                ...book.toMap(),
                                                                'userId':
                                                                    user.uid,
                                                                'listName':
                                                                    newListName,
                                                                'createdAt':
                                                                    FieldValue
                                                                        .serverTimestamp(),
                                                              });

                                                              if (context
                                                                  .mounted) {
                                                                ScaffoldMessenger.of(
                                                                        context)
                                                                    .showSnackBar(
                                                                  SnackBar(
                                                                    content: Text(
                                                                        'Added "${book.title}" to $newListName'),
                                                                  ),
                                                                );
                                                                Navigator.pop(
                                                                    context);
                                                              }
                                                            } catch (e) {
                                                              if (context
                                                                  .mounted) {
                                                                ScaffoldMessenger.of(
                                                                        context)
                                                                    .showSnackBar(
                                                                  SnackBar(
                                                                      content: Text(
                                                                          'Error creating list: $e')),
                                                                );
                                                              }
                                                            }
                                                          }
                                                        },
                                                        child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(16.0),
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons.add,
                                                                color: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .primary,
                                                              ),
                                                              const SizedBox(
                                                                  width: 8),
                                                              Text(
                                                                'Add New List',
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .titleMedium
                                                                    ?.copyWith(
                                                                      color: Theme.of(
                                                                              context)
                                                                          .colorScheme
                                                                          .primary,
                                                                    ),
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
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                    dialogContext),
                                                child: const Text('Cancel'),
                                              ),
                                            ],
                                          ),
                                        );

                                        if (selectedList == null) return;

                                        // Add book to selected list
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(user.uid)
                                            .collection('lists')
                                            .doc(selectedList['id'])
                                            .collection('books')
                                            .doc(book.isbn)
                                            .set({
                                          ...book.toMap(),
                                          'userId': user.uid,
                                          'createdAt':
                                              FieldValue.serverTimestamp(),
                                        });

                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Added "${book.title}" to ${selectedList['name']}'),
                                            ),
                                          );
                                          Navigator.pop(context);
                                        }
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
