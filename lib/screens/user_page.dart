import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../models/settings.dart' as app_settings;

class UserPage extends StatefulWidget {
  final String userId;
  final String username;

  const UserPage({
    super.key,
    required this.userId,
    required this.username,
  });

  @override
  _UserPageState createState() => _UserPageState();
}

class _UserPageState extends State<UserPage> {
  bool _isLoading = true;
  bool _isInitialized = false;
  bool _isFriend = false;
  bool _hasPendingRequest = false;
  String _bio = '';
  String _displayName = '';
  String? _base64Image;
  int _totalBooks = 0;
  int _totalPages = 0;
  String _favoriteGenre = '';
  String _favoriteAuthor = '';
  String _lastUpdated = '';
  List<String> _favoriteGenreTags = [];
  List<Map<String, dynamic>> _favoriteBooks = [];
  DateTime? _createdAt;
  int _friendCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;

        // Check if users are friends
        final friendsDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('friends')
            .doc(widget.userId)
            .get();

        // Check for pending friend request
        final requestDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('friendRequests')
            .doc(currentUser.uid)
            .get();

        // Get friend count
        final friendsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('friends')
            .get();

        // Load user's books to get statistics
        final booksSnapshot = await FirebaseFirestore.instance
            .collectionGroup('books')
            .where('userId', isEqualTo: widget.userId)
            .get();

        // Load favorite books
        final favoriteBooksSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('books')
            .where('isFavorite', isEqualTo: true)
            .get();

        if (mounted) {
          setState(() {
            _isFriend = friendsDoc.exists;
            _hasPendingRequest = requestDoc.exists;
            _bio = data['bio'] ?? '';
            _displayName = data['displayName'] ?? widget.username;
            _base64Image = data['profileImageBase64'];
            _totalBooks = booksSnapshot.docs.length;
            _totalPages = data['totalPages'] ?? 0;
            _favoriteGenre = data['favoriteGenre'] ?? '';
            _favoriteAuthor = data['favoriteAuthor'] ?? '';
            _lastUpdated = data['lastUpdated'] ?? '';
            _favoriteGenreTags =
                List<String>.from(data['favoriteGenreTags'] ?? []);
            _favoriteBooks = favoriteBooksSnapshot.docs
                .map((doc) => {
                      ...doc.data(),
                      'id': doc.id,
                    })
                .where((book) => book['listId'] != null)
                .toList();
            _createdAt = (data['createdAt'] as Timestamp?)?.toDate();
            _friendCount = friendsSnapshot.docs.length;
            _isLoading = false;
            _isInitialized = true;
          });
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialized = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading profile: $e')),
        );
      }
    }
  }

  Future<void> _handleFriendRequest() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      if (_isFriend) {
        // Remove friend
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('friends')
            .doc(widget.userId)
            .delete();

        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('friends')
            .doc(currentUser.uid)
            .delete();

        setState(() {
          _isFriend = false;
        });
      } else if (_hasPendingRequest) {
        // Cancel friend request
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('friendRequests')
            .doc(currentUser.uid)
            .delete();

        setState(() {
          _hasPendingRequest = false;
        });
      } else {
        // Get current user's username
        final currentUserDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();
        final currentUsername =
            currentUserDoc.data()?['username'] ?? 'Unknown User';

        // Send friend request
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('friendRequests')
            .doc(currentUser.uid)
            .set({
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending',
          'fromUserId': currentUser.uid,
          'fromUsername': currentUsername,
        });

        // Create notification for the other user
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .collection('notifications')
            .add({
          'type': 'friend_request',
          'title': 'New Friend Request',
          'message': '@$currentUsername wants to be your friend',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
          'fromUserId': currentUser.uid,
          'fromUsername': currentUsername,
          'toUserId': widget.userId,
        });

        setState(() {
          _hasPendingRequest = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final percentage =
        _totalBooks > 0 ? (_totalPages / _totalBooks * 100).round() : 0;

    // Calculate account age
    final accountAge = _createdAt != null
        ? DateTime.now().difference(_createdAt!)
        : const Duration();
    final days = accountAge.inDays;
    final hours = accountAge.inHours % 24;
    final minutes = accountAge.inMinutes % 60;

    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Info Card
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 5.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProfileHeader(days, hours, minutes),
                    const SizedBox(height: 16),
                    // Bio Section
                    if (_bio.isNotEmpty) ...[
                      Text(
                        'Bio',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _bio,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 5),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Favorites Card
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 5.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Favorite Books',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    if (_favoriteBooks.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32.0),
                          child: Text(
                            'This user has not selected any favorite books',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).hintColor,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _favoriteBooks.length,
                          padding: const EdgeInsets.only(bottom: 8),
                          itemBuilder: (context, index) {
                            final book = _favoriteBooks[index];
                            return Padding(
                              padding: const EdgeInsets.only(right: 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 120,
                                    height: 145,
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      image: book['imageUrl'] != null
                                          ? DecorationImage(
                                              image: NetworkImage(
                                                  book['imageUrl']),
                                              fit: BoxFit.cover,
                                            )
                                          : null,
                                      color: Colors.grey[200],
                                    ),
                                    child: book['imageUrl'] == null
                                        ? const Center(
                                            child: Icon(Icons.book, size: 50),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      book['title'] ?? 'Unknown Title',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Book Statistics Card
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 5.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Book Statistics',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatColumn('Total Books', _totalBooks.toString()),
                        _buildStatColumn('Read', _totalPages.toString()),
                        _buildStatColumn('Progress', '$percentage%'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _totalBooks > 0 ? _totalPages / _totalBooks : 0,
                      backgroundColor: Colors.grey[200],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Genres Card
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 10.0),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 5.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Favorite Genres',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_favoriteGenreTags.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16.0),
                            child: Text(
                              'This user has not selected any favorite genres',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context).hintColor,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _favoriteGenreTags.map((genre) {
                            return Chip(
                              label: Text(genre),
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(int days, int hours, int minutes) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            CircleAvatar(
              radius: 45,
              backgroundImage: _base64Image != null
                  ? MemoryImage(base64Decode(_base64Image!))
                  : null,
              child: _base64Image == null
                  ? const Icon(Icons.person, size: 45)
                  : null,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _handleFriendRequest,
              icon: Icon(
                _isFriend
                    ? Icons.person_remove
                    : _hasPendingRequest
                        ? Icons.hourglass_empty
                        : Icons.person_add,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 16,
              ),
              label: Text(
                _isFriend
                    ? 'Remove Friend'
                    : _hasPendingRequest
                        ? 'Request Sent'
                        : 'Add Friend',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 12,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isFriend
                    ? Colors.red
                    : _hasPendingRequest
                        ? Colors.grey
                        : Theme.of(context).colorScheme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(0, 0),
              ),
            ),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '@${widget.username}',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontSize:
                          Theme.of(context).textTheme.headlineSmall!.fontSize! *
                              0.8,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Account age: $days days, $hours hours, $minutes minutes',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.people,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$_friendCount ${_friendCount == 1 ? 'Friend' : 'Friends'}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatColumn(String label, String value) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: Theme.of(context).textTheme.titleMedium!.fontSize! * 0.95,
        );
    final smallStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: Theme.of(context).textTheme.bodySmall!.fontSize! * 0.95,
        );

    return Column(
      children: [
        Text(
          value,
          style: titleStyle,
        ),
        Text(
          label,
          style: smallStyle,
        ),
      ],
    );
  }
}
