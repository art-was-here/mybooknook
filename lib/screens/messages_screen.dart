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
  List<Map<String, dynamic>> _friends = [];
  List<String> _userSuggestions = [];
  bool _isSearching = false;
  final Map<String, Map<String, dynamic>> _userCache = {};
  bool _isInitialLoad = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _recipientController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _isInitialLoad = false;
          });
        }
        return;
      }

      // Load users and friends in parallel
      final futures = await Future.wait([
        FirebaseFirestore.instance
            .collection('users')
            .where('setupComplete', isEqualTo: true)
            .get(),
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('friends')
            .get(),
      ]);

      if (!mounted) return;

      final usersSnapshot = futures[0] as QuerySnapshot;
      final friendsSnapshot = futures[1] as QuerySnapshot;

      // Cache all user data at once
      final userDataMap = {
        for (var doc in usersSnapshot.docs)
          doc.id: doc.data() as Map<String, dynamic>
      };

      // Process friends list
      final friendsList = friendsSnapshot.docs.map((doc) {
        final friendId = doc.id;
        final friendData = doc.data() as Map<String, dynamic>;
        final userData = userDataMap[friendId] ?? {};

        return {
          'id': friendId,
          'username': friendData['username'] ?? 'Unknown',
          'displayName':
              userData['displayName'] ?? userData['username'] ?? 'Unknown',
        };
      }).toList();

      if (!mounted) return;

      setState(() {
        _users = usersSnapshot.docs.where((doc) => doc.id != user.uid).toList();
        _friends = friendsList;
        _userCache.addAll(userDataMap);
        _isInitialLoad = false;
      });
    } catch (e) {
      print('Error loading initial data: $e');
      if (mounted) {
        setState(() {
          _isInitialLoad = false;
        });
      }
    }
  }

  // Simplified method to get user data
  Map<String, dynamic> getUserData(String userId) {
    return _userCache[userId] ??
        {
          'username': 'Unknown User',
          'displayName': 'Unknown User',
          'profileImageBase64': null,
        };
  }

  void _showNewMessageSheet() {
    // Create local state for the modal
    List<Map<String, dynamic>> filteredFriends = [];
    List<String> userSuggestions = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        final screenHeight = MediaQuery.of(context).size.height;
        final messageBoxHeight = screenHeight * 0.2;

        return WillPopScope(
          onWillPop: () async {
            _messageController.clear();
            _recipientController.clear();
            return true;
          },
          child: StatefulBuilder(
            builder: (context, setModalState) {
              void searchUsers(String query) {
                final lowercaseQuery = query.toLowerCase();

                setModalState(() {
                  isSearching = query.isNotEmpty;
                  if (query.isEmpty) {
                    userSuggestions = [];
                    filteredFriends = [];
                  } else {
                    // Filter friends first
                    filteredFriends = _friends
                        .where((friend) =>
                            friend['username']
                                .toString()
                                .toLowerCase()
                                .contains(lowercaseQuery) ||
                            friend['displayName']
                                .toString()
                                .toLowerCase()
                                .contains(lowercaseQuery))
                        .toList();

                    // Also search other users if needed
                    userSuggestions = _users
                        .where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final username = data['username'] as String? ?? '';
                          return username.contains(lowercaseQuery);
                        })
                        .map((doc) =>
                            (doc.data() as Map<String, dynamic>)['displayName']
                                as String? ??
                            (doc.data() as Map<String, dynamic>)['username']
                                as String? ??
                            '')
                        .toList();
                  }
                });
              }

              return Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'New Message',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _recipientController,
                        decoration: InputDecoration(
                          labelText: 'Recipient Username',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          suffixIcon: isSearching
                              ? const Icon(Icons.search)
                              : const Icon(Icons.person),
                        ),
                        onChanged: searchUsers,
                      ),
                      if (isSearching &&
                          (filteredFriends.isNotEmpty ||
                              userSuggestions.isNotEmpty))
                        AnimatedSlide(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          offset: Offset.zero,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            opacity: 1.0,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.of(context).size.height * 0.2,
                              ),
                              margin: const EdgeInsets.only(top: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withOpacity(0.5),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ListView(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                children: [
                                  if (filteredFriends.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        'Friends',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                    ),
                                    ...List.generate(
                                      filteredFriends.length,
                                      (index) => ListTile(
                                        dense: true,
                                        leading: CircleAvatar(
                                          child: Text(filteredFriends[index]
                                                  ['displayName'][0]
                                              .toUpperCase()),
                                        ),
                                        title: Text(filteredFriends[index]
                                            ['displayName']),
                                        subtitle: Text(
                                            '@${filteredFriends[index]['username']}'),
                                        onTap: () {
                                          setModalState(() {
                                            _recipientController.text =
                                                filteredFriends[index]
                                                    ['username'];
                                            isSearching = false;
                                            filteredFriends = [];
                                            userSuggestions = [];
                                          });
                                        },
                                      ),
                                    ),
                                    if (userSuggestions.isNotEmpty)
                                      const Divider(),
                                  ],
                                  if (userSuggestions.isNotEmpty) ...[
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        'Other Users',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                    ),
                                    ...List.generate(
                                      userSuggestions.length,
                                      (index) => ListTile(
                                        dense: true,
                                        leading: const CircleAvatar(
                                          child: Icon(Icons.person_outline),
                                        ),
                                        title: Text(userSuggestions[index]),
                                        onTap: () {
                                          setModalState(() {
                                            _recipientController.text =
                                                userSuggestions[index];
                                            isSearching = false;
                                            filteredFriends = [];
                                            userSuggestions = [];
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: messageBoxHeight,
                        child: Stack(
                          children: [
                            TextField(
                              controller: _messageController,
                              decoration: InputDecoration(
                                labelText: 'Message',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                filled: true,
                                fillColor:
                                    Theme.of(context).colorScheme.surface,
                                contentPadding: const EdgeInsets.only(
                                  left: 16,
                                  right: 60,
                                  top: 16,
                                  bottom: 16,
                                ),
                              ),
                              maxLines: null,
                              expands: true,
                            ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.send, size: 22),
                                      onPressed: _sendMessage,
                                      style: IconButton.styleFrom(
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        foregroundColor: Theme.of(context)
                                            .colorScheme
                                            .onPrimary,
                                        padding: const EdgeInsets.all(8),
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
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

      if (mounted) {
        Navigator.pop(context); // Close the bottom sheet
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message sent successfully')),
        );
      }
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
      body: _isInitialLoad
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                        onPressed: _loadInitialData,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildChatsList(),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewMessageSheet,
        child: const Icon(Icons.message),
      ),
    );
  }

  Widget _buildChatsList() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Please sign in to view messages'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: user.uid)
          .orderBy('lastMessageTimestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final chats = snapshot.data?.docs ?? [];

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
          cacheExtent: 1000,
          itemBuilder: (context, index) {
            final chat = chats[index];
            final chatData = chat.data() as Map<String, dynamic>;

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

            // Get cached user data synchronously
            final userData = getUserData(otherUserId);
            final username = userData['displayName'] ??
                userData['username'] ??
                'Unknown User';
            final profileImage = userData['profileImageBase64'];

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                contentPadding: const EdgeInsets.only(left: 16, right: 8),
                leading: CircleAvatar(
                  backgroundImage: profileImage != null
                      ? MemoryImage(base64Decode(profileImage))
                      : null,
                  child: profileImage == null ? const Icon(Icons.person) : null,
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
                                  onPressed: () => Navigator.of(context).pop(),
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
