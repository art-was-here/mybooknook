import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:math' as Math;
import 'dart:convert';
import '../services/notification_service.dart';
import 'chat_room_screen.dart';

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

      print('Loading users from Firestore...');
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('setupComplete', isEqualTo: true)
          .get();

      print('Found ${querySnapshot.docs.length} users in total');

      setState(() {
        _users = querySnapshot.docs
            .where((doc) => doc.id != user.uid) // Exclude current user
            .toList();

        print('Loaded ${_users.length} users (excluding current user)');
        // Debug: Print the first few usernames
        if (_users.isNotEmpty) {
          print('Sample usernames:');
          for (var i = 0; i < Math.min(5, _users.length); i++) {
            final userData = _users[i].data() as Map<String, dynamic>;
            print(
                '  - ${userData['username']} (display: ${userData['displayName']})');
          }
        }
      });
    } catch (e) {
      print('Error loading users: $e');
    }
  }

  void _searchUsers(String query) {
    final lowercaseQuery = query.toLowerCase(); // Convert query to lowercase

    setState(() {
      _isSearching = query.isNotEmpty;
      if (query.isEmpty) {
        _userSuggestions = [];
      } else {
        _userSuggestions = _users
            .where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final username = data['username'] as String? ?? '';
              return username.contains(
                  lowercaseQuery); // Username is already stored in lowercase
            })
            .map((doc) =>
                (doc.data() as Map<String, dynamic>)['displayName']
                    as String? ??
                (doc.data() as Map<String, dynamic>)['username'] as String? ??
                '')
            .toList();
      }
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    final recipientUsername = _recipientController.text.trim().toLowerCase();

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
      print('Searching for user with username: "$recipientUsername"');

      // Find the recipient user by username (stored as lowercase in database)
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: recipientUsername)
          .limit(1)
          .get();

      print('Query returned ${querySnapshot.docs.length} results');

      if (querySnapshot.docs.isEmpty) {
        print('No user found with username: $recipientUsername');

        // Debug: Let's check if the user exists with a case-insensitive search
        final allUsersSnapshot =
            await FirebaseFirestore.instance.collection('users').get();

        print('Total users in database: ${allUsersSnapshot.docs.length}');

        final matchingUsers = allUsersSnapshot.docs.where((doc) {
          final userData = doc.data();
          final username = userData['username'] as String? ?? '';
          return username.toLowerCase() == recipientUsername.toLowerCase();
        }).toList();

        print('Users with case-insensitive match: ${matchingUsers.length}');
        if (matchingUsers.isNotEmpty) {
          for (var doc in matchingUsers) {
            final userData = doc.data();
            print(
                'Found user: ${userData['username']} (display: ${userData['displayName']})');
          }
        }

        setState(() {
          _errorMessage = 'User not found: $recipientUsername';
          _isLoading = false;
        });
        return;
      }

      final recipientUserId = querySnapshot.docs.first.id;
      final recipientData = querySnapshot.docs.first.data();
      print('Found recipient: ID=$recipientUserId, data=$recipientData');

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'You must be logged in to send messages';
          _isLoading = false;
        });
        return;
      }

      // Get current user's data
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      final currentUsername = currentUserDoc.data()?['displayName'] ??
          currentUserDoc.data()?['username'] ??
          'Unknown User';

      // Create a chat ID that's the same regardless of who sends the message
      final chatId = _getChatId(currentUser.uid, recipientUserId);

      // Add message to the chat collection
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'senderId': currentUser.uid,
        'senderName': currentUsername,
        'recipientId': recipientUserId,
        'recipientName': recipientData['displayName'] ??
            recipientData['username'] ??
            'Unknown User',
        'text': message,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      // Update or create chat metadata document
      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
        'participants': [currentUser.uid, recipientUserId],
        'lastMessage': message,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'lastMessageSenderId': currentUser.uid,
      }, SetOptions(merge: true));

      // Also create a notification for the recipient
      await _notificationService.sendMessageToUser(
        recipientUserId: recipientUserId,
        title: 'New Message',
        body: message,
        data: {
          'type': 'direct_message',
          'messageText': message,
          'senderId': currentUser.uid,
          'senderName': currentUsername,
        },
      );

      // Clear message field and recipient
      _messageController.clear();
      _recipientController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent successfully')),
      );

      // Removed the automatic navigation to chat room
    } catch (e) {
      print('Error sending message: $e');
      setState(() {
        _errorMessage = 'Error sending message: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Create a consistent chat ID regardless of who initiated the chat
  String _getChatId(String userId1, String userId2) {
    return userId1.compareTo(userId2) < 0
        ? '${userId1}_$userId2'
        : '${userId2}_$userId1';
  }

  // Add a method to delete a conversation
  Future<void> _deleteConversation(String chatId) async {
    try {
      // Show a loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text("Deleting conversation..."),
              ],
            ),
          );
        },
      );

      // Get all messages in the chat
      final messagesSnapshot = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .get();

      // Delete all messages in a batch
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in messagesSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // Delete the chat document itself
      batch.delete(FirebaseFirestore.instance.collection('chats').doc(chatId));

      // Commit the batch
      await batch.commit();

      // Close the loading dialog
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Conversation deleted')),
      );
    } catch (e) {
      // Close the loading dialog if open
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      print('Error deleting conversation: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting conversation: ${e.toString()}')),
      );
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
                  'Your Conversations',
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
            child: _buildChatsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildChatsList() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please sign in to view messages'));
    }

    print('Building chats list for user: ${user.uid}');

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: user.uid)
          .orderBy('lastMessageTimestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          print('Waiting for chats data...');
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          print('Error in chats stream: ${snapshot.error}');
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final chats = snapshot.data?.docs ?? [];
        print('Retrieved ${chats.length} chats');

        if (chats.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_outlined,
                  size: 64,
                  color: Theme.of(context).disabledColor,
                ),
                const SizedBox(height: 16),
                Text(
                  'No conversations yet',
                  style: TextStyle(color: Theme.of(context).disabledColor),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: chats.length,
          itemBuilder: (context, index) {
            final chat = chats[index];
            final chatData = chat.data() as Map<String, dynamic>;

            print('Processing chat: ${chat.id}, data: $chatData');

            // Get the other participant's ID
            final participants =
                List<String>.from(chatData['participants'] ?? []);
            final otherUserId = participants.firstWhere(
              (id) => id != user.uid,
              orElse: () => 'unknown',
            );

            final lastMessage = chatData['lastMessage'] as String? ?? '';
            final lastMessageTimestamp =
                chatData['lastMessageTimestamp'] as Timestamp?;
            final isLastMessageFromMe =
                chatData['lastMessageSenderId'] == user.uid;

            String formattedDate = 'Just now';
            if (lastMessageTimestamp != null) {
              final now = DateTime.now();
              final date = lastMessageTimestamp.toDate();

              if (now.difference(date).inDays > 0) {
                formattedDate = DateFormat('MMM d').format(date);
              } else {
                formattedDate = DateFormat('h:mm a').format(date);
              }
            }

            // We need to fetch the other user's details
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(otherUserId)
                  .get(),
              builder: (context, userSnapshot) {
                if (userSnapshot.hasError) {
                  print(
                      'Error fetching user ${otherUserId}: ${userSnapshot.error}');
                }

                String username = 'Unknown User';
                String? profileImage;

                if (userSnapshot.hasData && userSnapshot.data != null) {
                  final userData =
                      userSnapshot.data!.data() as Map<String, dynamic>?;
                  if (userData != null) {
                    username = userData['displayName'] ??
                        userData['username'] ??
                        'Unknown User';
                    profileImage = userData['profileImageBase64'];
                    print('Found user: $username');
                  }
                }

                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    contentPadding: const EdgeInsets.only(left: 16, right: 8),
                    leading: CircleAvatar(
                      backgroundImage: profileImage != null
                          ? MemoryImage(base64Decode(profileImage))
                          : null,
                      child: profileImage == null
                          ? const Icon(Icons.person)
                          : null,
                    ),
                    title: Text(username),
                    subtitle: Row(
                      children: [
                        if (isLastMessageFromMe)
                          const Icon(Icons.done, size: 12, color: Colors.grey),
                        if (isLastMessageFromMe) const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            lastMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formattedDate,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).disabledColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _buildUnreadBadge(chat.id, user.uid),
                          ],
                        ),
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            if (value == 'delete') {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete Conversation'),
                                  content: Text(
                                      'Are you sure you want to delete your conversation with $username? This cannot be undone.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('CANCEL'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                        _deleteConversation(chat.id);
                                      },
                                      child: const Text('DELETE'),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete),
                                  SizedBox(width: 8),
                                  Text('Delete conversation'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    onTap: () {
                      print('Opening chat with user: $otherUserId ($username)');
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatRoomScreen(
                            otherUserId: otherUserId,
                            otherUsername: username,
                            otherUserProfileImage: profileImage,
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildUnreadBadge(String chatId, String userId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('recipientId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data?.docs.length ?? 0;

        if (unreadCount == 0) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            unreadCount.toString(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}
