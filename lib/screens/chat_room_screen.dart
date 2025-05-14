import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

class ChatRoomScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUsername;
  final String? otherUserProfileImage;

  const ChatRoomScreen({
    Key? key,
    required this.otherUserId,
    required this.otherUsername,
    this.otherUserProfileImage,
  }) : super(key: key);

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  String? _currentUserId;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _getCurrentUserInfo();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _currentUserId = user.uid;

    // Get current user's username
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (userDoc.exists) {
      setState(() {
        _currentUsername = userDoc.data()?['displayName'] ??
            userDoc.data()?['username'] ??
            'Me';
      });
    }
  }

  Future<void> _sendMessage() async {
    final messageText = _messageController.text.trim();
    if (messageText.isEmpty || _currentUserId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final timestamp = FieldValue.serverTimestamp();

      // Create a chat ID that's the same regardless of who sends the message
      final chatId = _getChatId(_currentUserId!, widget.otherUserId);

      // Add message to the chat collection
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .add({
        'senderId': _currentUserId,
        'senderName': _currentUsername,
        'recipientId': widget.otherUserId,
        'recipientName': widget.otherUsername,
        'text': messageText,
        'timestamp': timestamp,
        'isRead': false,
      });

      // Update or create chat metadata document
      await FirebaseFirestore.instance.collection('chats').doc(chatId).set({
        'participants': [_currentUserId, widget.otherUserId],
        'lastMessage': messageText,
        'lastMessageTimestamp': timestamp,
        'lastMessageSenderId': _currentUserId,
      }, SetOptions(merge: true));

      // Clear the text field
      _messageController.clear();

      // Scroll to the bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending message: $e')),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: widget.otherUserProfileImage != null
                  ? MemoryImage(base64Decode(widget.otherUserProfileImage!))
                  : null,
              child: widget.otherUserProfileImage == null
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(widget.otherUsername),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _buildMessageList(),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_currentUserId == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final chatId = _getChatId(_currentUserId!, widget.otherUserId);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
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
            child: Text(
              'No messages yet. Say hello!',
              style: TextStyle(color: Theme.of(context).disabledColor),
            ),
          );
        }

        // Mark messages as read
        _markMessagesAsRead(messages);

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final data = message.data() as Map<String, dynamic>;
            final isMe = data['senderId'] == _currentUserId;
            final timestamp = data['timestamp'] as Timestamp?;

            String formattedTime = '';
            if (timestamp != null) {
              formattedTime = DateFormat('h:mm a').format(timestamp.toDate());
            }

            return _buildMessageBubble(
              message: data['text'] ?? '',
              isMe: isMe,
              time: formattedTime,
              isRead: data['isRead'] ?? false,
            );
          },
        );
      },
    );
  }

  Future<void> _markMessagesAsRead(List<QueryDocumentSnapshot> messages) async {
    if (_currentUserId == null) return;

    final batch = FirebaseFirestore.instance.batch();
    bool hasUnreadMessages = false;

    for (final message in messages) {
      final data = message.data() as Map<String, dynamic>;
      if (data['senderId'] != _currentUserId && data['isRead'] == false) {
        batch.update(message.reference, {'isRead': true});
        hasUnreadMessages = true;
      }
    }

    if (hasUnreadMessages) {
      await batch.commit();
    }
  }

  Widget _buildMessageBubble({
    required String message,
    required bool isMe,
    required String time,
    required bool isRead,
  }) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(
                color: isMe
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? Theme.of(context)
                            .colorScheme
                            .onPrimary
                            .withOpacity(0.7)
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7),
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isRead ? Icons.done_all : Icons.done,
                    size: 12,
                    color: isRead
                        ? Colors.blue
                        : Theme.of(context)
                            .colorScheme
                            .onPrimary
                            .withOpacity(0.7),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, bottomPadding + 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Type a message',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            onPressed: _isLoading ? null : _sendMessage,
            mini: true,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
