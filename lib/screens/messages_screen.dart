import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({Key? key}) : super(key: key);

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _recipientController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  final NotificationService _notificationService = NotificationService();
  List<DocumentSnapshot> _users = [];
  List<String> _userSuggestions = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('setupComplete', isEqualTo: true)
          .get();

      setState(() {
        _users = querySnapshot.docs
            .where((doc) => doc.id != user.uid) // Exclude current user
            .toList();
      });
    } catch (e) {
      print('Error loading users: $e');
    }
  }

  void _searchUsers(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      if (query.isEmpty) {
        _userSuggestions = [];
      } else {
        _userSuggestions = _users
            .where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final username = data['username'] as String? ?? '';
              return username.toLowerCase().contains(query.toLowerCase());
            })
            .map((doc) =>
                (doc.data() as Map<String, dynamic>)['username'] as String? ??
                '')
            .toList();
      }
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    final recipientUsername = _recipientController.text.trim();

    if (message.isEmpty || recipientUsername.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter both recipient username and message';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Find the recipient user by username
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: recipientUsername)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        setState(() {
          _errorMessage = 'User not found: $recipientUsername';
          _isLoading = false;
        });
        return;
      }

      final recipientUserId = querySnapshot.docs.first.id;

      // Send the message
      await _notificationService.sendMessageToUser(
        recipientUserId: recipientUserId,
        title: 'New Message',
        body: message,
        data: {
          'type': 'direct_message',
          'messageText': message,
        },
      );

      // Clear message field
      _messageController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent successfully')),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Error sending message: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _recipientController,
                  decoration: const InputDecoration(
                    labelText: 'Recipient Username',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: _searchUsers,
                ),
                if (_isSearching && _userSuggestions.isNotEmpty)
                  Container(
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ListView.builder(
                      itemCount: _userSuggestions.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(_userSuggestions[index]),
                          onTap: () {
                            setState(() {
                              _recipientController.text =
                                  _userSuggestions[index];
                              _isSearching = false;
                            });
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    prefixIcon: Icon(Icons.message),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 8),
                if (_errorMessage != null)
                  Text(
                    _errorMessage!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _sendMessage,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send Message'),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Your Messages',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                  onPressed: () {
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _buildMessagesList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please sign in to view messages'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final messages = snapshot.data?.docs ?? [];

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.message_outlined,
                  size: 64,
                  color: Theme.of(context).disabledColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'No messages yet',
                  style: TextStyle(color: Theme.of(context).disabledColor),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final data = message.data() as Map<String, dynamic>;
            final isRead = data['isRead'] as bool? ?? false;
            final timestamp = data['timestamp'] as Timestamp?;

            String formattedDate = 'Just now';
            if (timestamp != null) {
              final date = timestamp.toDate();
              formattedDate = DateFormat('MMM d, y • h:mm a').format(date);
            }

            return Dismissible(
              key: Key(message.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                color: Colors.red,
                child: const Icon(Icons.delete, color: Colors.white),
              ),
              onDismissed: (_) async {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('messages')
                    .doc(message.id)
                    .delete();
              },
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isRead
                        ? Theme.of(context).disabledColor
                        : Theme.of(context).colorScheme.primary,
                    child: Icon(
                      Icons.message,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          data['title'] ?? 'No title',
                          style: TextStyle(
                            fontWeight:
                                isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['body'] ?? 'No message',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'From: ${data['senderName'] ?? 'Unknown'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).disabledColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  onTap: () async {
                    if (!isRead) {
                      await _notificationService.markMessageAsRead(message.id);
                    }

                    // Show message details
                    if (mounted) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(data['title'] ?? 'Message'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('From: ${data['senderName'] ?? 'Unknown'}'),
                              Text('Date: $formattedDate'),
                              const Divider(),
                              Text(data['body'] ?? 'No message content'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
