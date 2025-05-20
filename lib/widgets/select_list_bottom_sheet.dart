import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';

class SelectListBottomSheet {
  static Future<Map<String, String>?> show(
    BuildContext context,
    Book book, {
    VoidCallback? onListCreated,
  }) async {
    final user = FirebaseAuth.instance.currentUser!;
    final TextEditingController newListController = TextEditingController();
    bool isCreatingNewList = false;

    // Get user's lists
    final listsSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('lists')
        .where('name', isNotEqualTo: 'Library')
        .get();

    final lists = listsSnapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': doc.id,
        'name': data['name'] as String? ?? 'Unknown List',
      };
    }).toList();

    if (!context.mounted) return null;

    // Show bottom sheet
    return await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: DraggableScrollableSheet(
                initialChildSize: 0.6,
                maxChildSize: 0.9,
                minChildSize: 0.4,
                expand: false,
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Column(
                      children: [
                        // Handle and title
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          height: 5,
                          width: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2.5),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'Select List',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),

                        // List content
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.zero,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                              ),
                            ),
                            child: ListView(
                              controller: scrollController,
                              children: [
                                ...lists.map((list) => ListTile(
                                      title: Text(list['name']!),
                                      onTap: () async {
                                        // Add book to selected list
                                        await FirebaseFirestore.instance
                                            .collection('users')
                                            .doc(user.uid)
                                            .collection('lists')
                                            .doc(list['id'])
                                            .collection('books')
                                            .doc(book.isbn)
                                            .set({
                                          ...book.toMap(),
                                          'userId': user.uid,
                                          'listName': list['name'],
                                          'createdAt':
                                              FieldValue.serverTimestamp(),
                                        });

                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Added "${book.title}" to ${list['name']}'),
                                            ),
                                          );

                                          // Refresh lists in parent
                                          if (onListCreated != null) {
                                            onListCreated();
                                          }

                                          Navigator.pop(sheetContext, list);
                                        }
                                      },
                                    )),

                                // Add new list option
                                if (!isCreatingNewList)
                                  ListTile(
                                    leading: Icon(
                                      Icons.add,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    title: Text(
                                      'Create New List',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onTap: () {
                                      setModalState(() {
                                        isCreatingNewList = true;
                                      });
                                    },
                                  ),

                                // New list creation UI
                                if (isCreatingNewList)
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Column(
                                      children: [
                                        TextField(
                                          controller: newListController,
                                          autofocus: true,
                                          decoration: InputDecoration(
                                            labelText: 'List Name',
                                            border: InputBorder.none,
                                            suffixIcon: IconButton(
                                              icon: const Icon(Icons.close),
                                              onPressed: () {
                                                setModalState(() {
                                                  isCreatingNewList = false;
                                                  newListController.clear();
                                                });
                                              },
                                            ),
                                          ),
                                          onSubmitted: (value) async {
                                            if (value.trim().isNotEmpty) {
                                              try {
                                                // Create new list
                                                final newListRef =
                                                    await FirebaseFirestore
                                                        .instance
                                                        .collection('users')
                                                        .doc(user.uid)
                                                        .collection('lists')
                                                        .add({
                                                  'name': value.trim(),
                                                  'createdAt': FieldValue
                                                      .serverTimestamp(),
                                                });

                                                // Add book to the new list
                                                await FirebaseFirestore.instance
                                                    .collection('users')
                                                    .doc(user.uid)
                                                    .collection('lists')
                                                    .doc(newListRef.id)
                                                    .collection('books')
                                                    .doc(book.isbn)
                                                    .set({
                                                  ...book.toMap(),
                                                  'userId': user.uid,
                                                  'listName': value.trim(),
                                                  'createdAt': FieldValue
                                                      .serverTimestamp(),
                                                });

                                                // Manually force a refresh of the list names cache
                                                final prefs =
                                                    await SharedPreferences
                                                        .getInstance();
                                                await prefs
                                                    .remove('list_names_cache');
                                                await prefs.remove(
                                                    'list_names_timestamp');

                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                          'Added "${book.title}" to ${value.trim()}'),
                                                    ),
                                                  );

                                                  // Call the callback if provided to refresh the parent screen
                                                  if (onListCreated != null) {
                                                    onListCreated();
                                                  }

                                                  Navigator.pop(sheetContext, {
                                                    'id': newListRef.id,
                                                    'name': value.trim(),
                                                  });
                                                }
                                              } catch (e) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                          'Error creating list: $e'),
                                                    ),
                                                  );
                                                }
                                              }
                                            }
                                          },
                                        ),
                                        const Divider(),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            TextButton(
                                              onPressed: () {
                                                setModalState(() {
                                                  isCreatingNewList = false;
                                                  newListController.clear();
                                                });
                                              },
                                              child: const Text('Cancel'),
                                            ),
                                            const SizedBox(width: 8),
                                            ElevatedButton(
                                              onPressed: () async {
                                                final value = newListController
                                                    .text
                                                    .trim();
                                                if (value.isNotEmpty) {
                                                  try {
                                                    // Create new list
                                                    final newListRef =
                                                        await FirebaseFirestore
                                                            .instance
                                                            .collection('users')
                                                            .doc(user.uid)
                                                            .collection('lists')
                                                            .add({
                                                      'name': value,
                                                      'createdAt': FieldValue
                                                          .serverTimestamp(),
                                                    });

                                                    // Add book to the new list
                                                    await FirebaseFirestore
                                                        .instance
                                                        .collection('users')
                                                        .doc(user.uid)
                                                        .collection('lists')
                                                        .doc(newListRef.id)
                                                        .collection('books')
                                                        .doc(book.isbn)
                                                        .set({
                                                      ...book.toMap(),
                                                      'userId': user.uid,
                                                      'listName': value,
                                                      'createdAt': FieldValue
                                                          .serverTimestamp(),
                                                    });

                                                    // Manually force a refresh of the list names cache
                                                    final prefs =
                                                        await SharedPreferences
                                                            .getInstance();
                                                    await prefs.remove(
                                                        'list_names_cache');
                                                    await prefs.remove(
                                                        'list_names_timestamp');

                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'Added "${book.title}" to $value'),
                                                        ),
                                                      );

                                                      // Call the callback if provided to refresh the parent screen
                                                      if (onListCreated !=
                                                          null) {
                                                        onListCreated();
                                                      }

                                                      Navigator.pop(
                                                          sheetContext, {
                                                        'id': newListRef.id,
                                                        'name': value,
                                                      });
                                                    }
                                                  } catch (e) {
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                          content: Text(
                                                              'Error creating list: $e'),
                                                        ),
                                                      );
                                                    }
                                                  }
                                                }
                                              },
                                              child: const Text('Create'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
