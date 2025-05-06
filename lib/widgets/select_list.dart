import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/book.dart';

class SelectListDialog {
  static Future<Map<String, String>?> show(
      BuildContext context, Book book) async {
    try {
      final user = FirebaseAuth.instance.currentUser!;

      // Show list selection dialog
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

      if (!context.mounted) return null;

      final selectedList = await showDialog<Map<String, String>>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('Select List'),
          content: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: lists.length,
                    itemBuilder: (context, index) {
                      final list = lists[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: InkWell(
                          onTap: () => Navigator.pop(dialogContext, list),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              list['name']!,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: InkWell(
                      onTap: () async {
                        Navigator.pop(dialogContext);
                        final newListName = await showDialog<String>(
                          context: context,
                          builder: (BuildContext newListContext) {
                            final TextEditingController textController =
                                TextEditingController();
                            return AlertDialog(
                              title: const Text('New List'),
                              content: TextField(
                                controller: textController,
                                autofocus: true,
                                decoration: const InputDecoration(
                                  labelText: 'List Name',
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (value) {
                                  if (value.trim().isNotEmpty) {
                                    Navigator.pop(newListContext, value.trim());
                                  }
                                },
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(newListContext),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    final value = textController.text.trim();
                                    if (value.isNotEmpty) {
                                      Navigator.pop(newListContext, value);
                                    }
                                  },
                                  child: const Text('Create'),
                                ),
                              ],
                            );
                          },
                        );

                        if (newListName != null && newListName.isNotEmpty) {
                          try {
                            final user = FirebaseAuth.instance.currentUser!;
                            final newListRef = await FirebaseFirestore.instance
                                .collection('users')
                                .doc(user.uid)
                                .collection('lists')
                                .add({
                              'name': newListName,
                              'createdAt': FieldValue.serverTimestamp(),
                            });

                            // Add the book to the new list
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
                              'listName': newListName,
                              'createdAt': FieldValue.serverTimestamp(),
                            });

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Added "${book.title}" to $newListName'),
                                ),
                              );
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Error creating list: $e')),
                              );
                            }
                          }
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Add New List',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
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
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );

      if (selectedList == null) return null;

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
        'listName': selectedList['name'],
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${book.title}" to ${selectedList['name']}'),
          ),
        );
      }

      return selectedList;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding book: $e')),
        );
      }
      return null;
    }
  }
}
