import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'user_page.dart';
import 'package:flutter/gestures.dart';
import '../services/book_service.dart';
import '../widgets/scan_book_details_card.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .orderBy('timestamp', descending: true)
          .get();

      if (mounted) {
        setState(() {
          _notifications = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              ...data,
            };
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading notifications: $e')),
        );
      }
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .doc(notificationId)
          .update({'isRead': true});

      setState(() {
        final index =
            _notifications.indexWhere((n) => n['id'] == notificationId);
        if (index != -1) {
          _notifications[index]['isRead'] = true;
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error marking notification as read: $e')),
        );
      }
    }
  }

  Future<void> _deleteNotification(String notificationId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notifications')
          .doc(notificationId)
          .delete();

      setState(() {
        _notifications.removeWhere((n) => n['id'] == notificationId);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting notification: $e')),
        );
      }
    }
  }

  Future<void> _handleNotificationTap(Map<String, dynamic> notification) async {
    if (notification['isRead'] != true) {
      await _markAsRead(notification['id']);
    }

    // Handle different notification types
    switch (notification['type']) {
      case 'friend_request':
        _showFriendRequestDialog(notification);
        break;
      case 'book_share':
        _handleBookShare(notification);
        break;
      // Add other notification types here
    }
  }

  Future<void> _showFriendRequestDialog(
      Map<String, dynamic> notification) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final fromUserId = notification['fromUserId'];
    final fromUsername = notification['fromUsername'];

    if (fromUserId == null) return;

    // Get current user's username from Firestore
    final currentUserDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();
    final currentUsername =
        currentUserDoc.data()?['username'] ?? 'Unknown User';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Friend Request'),
        content: Text('@$fromUsername wants to be your friend'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Decline'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (result == null) return;

    try {
      if (result) {
        // Accept friend request
        final batch = FirebaseFirestore.instance.batch();

        // Add to friends collection for both users
        batch.set(
          FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .collection('friends')
              .doc(fromUserId),
          {
            'timestamp': FieldValue.serverTimestamp(),
            'username': fromUsername,
          },
        );

        batch.set(
          FirebaseFirestore.instance
              .collection('users')
              .doc(fromUserId)
              .collection('friends')
              .doc(currentUser.uid),
          {
            'timestamp': FieldValue.serverTimestamp(),
            'username': currentUsername,
          },
        );

        // Delete the friend request
        batch.delete(
          FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .collection('friendRequests')
              .doc(fromUserId),
        );

        // Delete the notification
        batch.delete(
          FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .collection('notifications')
              .doc(notification['id']),
        );

        // Create notification for the sender
        final notificationData = {
          'type': 'friend_request_accepted',
          'title': 'Friend Request Accepted',
          'message': '@$currentUsername accepted your friend request',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'fromUserId': currentUser.uid,
          'fromUsername': currentUsername,
          'toUserId': fromUserId,
        };

        print(
            'DEBUG: Creating notification with data: $notificationData'); // Debug print

        batch.set(
          FirebaseFirestore.instance
              .collection('users')
              .doc(fromUserId)
              .collection('notifications')
              .doc(),
          notificationData,
        );

        await batch.commit();

        // Update local state
        setState(() {
          _notifications.removeWhere((n) => n['id'] == notification['id']);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Friend request accepted')),
          );
        }
      } else {
        // Decline friend request
        final batch = FirebaseFirestore.instance.batch();

        // Delete the friend request
        batch.delete(
          FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .collection('friendRequests')
              .doc(fromUserId),
        );

        // Delete the notification
        batch.delete(
          FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .collection('notifications')
              .doc(notification['id']),
        );

        await batch.commit();

        // Update local state
        setState(() {
          _notifications.removeWhere((n) => n['id'] == notification['id']);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Friend request declined')),
          );
        }
      }
    } catch (e) {
      print('DEBUG: Error in friend request handling: $e'); // Debug print
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _handleBookShare(Map<String, dynamic> notification) async {
    try {
      final isbn = notification['bookIsbn'];
      if (isbn == null) {
        throw Exception('No ISBN found in notification');
      }

      // Create BookService instance
      final bookService = BookService(context);

      // Fetch book details
      final book = await bookService.fetchBookDetails(isbn);
      if (book == null) {
        throw Exception('Book not found');
      }

      // Get user's lists
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final listsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .get();

      final Map<String, String> lists = {};
      for (var doc in listsSnapshot.docs) {
        lists[doc.id] = doc.data()['name'] as String;
      }

      if (!mounted) return;

      // Show the book details card
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (BuildContext context) {
          return ScanBookDetailsCard(
            book: book,
            bookService: bookService,
            lists: lists,
            onClose: () {
              Navigator.pop(context);
            },
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening book: $e')),
        );
      }
    }
  }

  Widget _buildNotificationMessage(Map<String, dynamic> notification) {
    final message = notification['message'] ?? '';
    final fromUsername = notification['fromUsername'] ?? '';
    final fromUserId = notification['fromUserId'];

    print(
        'DEBUG: Building notification message for type: ${notification['type']}');
    print('DEBUG: fromUsername: $fromUsername');
    print('DEBUG: fromUserId: $fromUserId');
    print('DEBUG: Full notification data: $notification');

    if (notification['type'] == 'friend_request' ||
        notification['type'] == 'friend_request_accepted') {
      if (fromUsername.isEmpty) {
        print('DEBUG: Warning - empty username for notification');
        return Text(
            'Someone ${notification['type'] == 'friend_request' ? 'wants to be your friend' : 'accepted your friend request'}');
      }

      return RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyMedium,
          children: [
            const TextSpan(text: '@'),
            TextSpan(
              text: fromUsername,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  if (fromUserId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserPage(
                          userId: fromUserId,
                          username: fromUsername,
                        ),
                      ),
                    );
                  }
                },
            ),
            TextSpan(
              text: notification['type'] == 'friend_request'
                  ? ' wants to be your friend'
                  : ' accepted your friend request',
            ),
          ],
        ),
      );
    }

    return Text(message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (_notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear All Notifications'),
                    content: const Text(
                        'Are you sure you want to delete all notifications?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete All'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  try {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) return;

                    final batch = FirebaseFirestore.instance.batch();
                    for (var notification in _notifications) {
                      final docRef = FirebaseFirestore.instance
                          .collection('users')
                          .doc(user.uid)
                          .collection('notifications')
                          .doc(notification['id']);
                      batch.delete(docRef);
                    }
                    await batch.commit();

                    setState(() {
                      _notifications.clear();
                    });
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Error clearing notifications: $e')),
                      );
                    }
                  }
                }
              },
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 64,
                        color: Theme.of(context).hintColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications yet',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).hintColor,
                                ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    final timestamp =
                        (notification['timestamp'] as Timestamp).toDate();
                    final formattedDate =
                        DateFormat('MMM d, y • h:mm a').format(timestamp);

                    return Dismissible(
                      key: Key(notification['id']),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (direction) {
                        _deleteNotification(notification['id']);
                      },
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: notification['isRead'] == true
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.primary,
                          child: Icon(
                            _getNotificationIcon(notification['type']),
                            color: notification['isRead'] == true
                                ? Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer
                                : Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                        title: Text(notification['title'] ?? 'Notification'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildNotificationMessage(notification),
                            const SizedBox(height: 4),
                            Text(
                              formattedDate,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        onTap: () {
                          if (notification['isRead'] != true) {
                            _markAsRead(notification['id']);
                          }
                          _handleNotificationTap(notification);
                        },
                      ),
                    );
                  },
                ),
    );
  }

  IconData _getNotificationIcon(String? type) {
    switch (type) {
      case 'friend_request':
        return Icons.person_add;
      case 'book_recommendation':
        return Icons.book;
      case 'list_share':
        return Icons.share;
      case 'achievement':
        return Icons.emoji_events;
      default:
        return Icons.notifications;
    }
  }
}
