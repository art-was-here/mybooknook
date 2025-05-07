import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/settings.dart' as app_settings;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bioController = TextEditingController();
  final List<String> _selectedGenres = [];
  final List<String> _availableGenres = [
    'Fiction',
    'Non-Fiction',
    'Mystery',
    'Sci-Fi',
    'Fantasy',
    'Romance',
    'Thriller',
    'Horror',
    'Biography',
    'History',
    'Poetry',
    'Self-Help',
    'Business',
    'Technology',
    'Art',
    'Music',
  ];
  File? _imageFile;
  String? _base64Image;
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isInitialized = false;
  String _favoriteGenre = '';
  String _favoriteAuthor = '';
  String _lastUpdated = '';
  String _aboutMe = '';
  List<String> _favoriteGenreTags = [];
  int _totalBooks = 0;
  int _totalPages = 0;
  List<Map<String, dynamic>> _favoriteBooks = [];
  String _username = '';
  DateTime? _birthday;
  int _friendCount = 0;

  @override
  void initState() {
    super.initState();
    print('initState: Starting profile load');
    _initializeData();
  }

  @override
  void dispose() {
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    print('DEBUG: -------- Profile Loading Process Started --------');
    print('DEBUG: Starting initialization');

    // Load cached data first
    await _loadCachedData();
    await _loadBookStats();

    // Then sync with Firebase if needed
    await _syncWithFirebase();

    print('DEBUG: -------- Profile Loading Process Completed --------');

    if (mounted) {
      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _syncWithFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;

        // Check if we need to update local data
        bool needsUpdate = false;

        // Get friend count
        final friendsSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('friends')
            .get();

        final newFriendCount = friendsSnapshot.docs.length;
        if (newFriendCount != _friendCount) {
          _friendCount = newFriendCount;
          needsUpdate = true;
        }

        // Check profile image
        final newBase64Image = data['profileImageBase64'];
        if (newBase64Image != null && newBase64Image != _base64Image) {
          _base64Image = newBase64Image;
          needsUpdate = true;
        }

        // Check username
        final newUsername = data['username'] ?? '';
        if (newUsername != _username) {
          _username = newUsername;
          needsUpdate = true;
        }

        // Check bio
        final newBio = data['bio'] ?? '';
        if (newBio != _aboutMe) {
          _aboutMe = newBio;
          _bioController.text = newBio;
          needsUpdate = true;
        }

        // Check other data
        final newTotalBooks = data['totalBooks'] ?? 0;
        final newTotalPages = data['totalPages'] ?? 0;
        final newFavoriteGenre = data['favoriteGenre'] ?? '';
        final newFavoriteAuthor = data['favoriteAuthor'] ?? '';
        final newLastUpdated = data['lastUpdated'] ?? '';
        final newFavoriteGenreTags =
            List<String>.from(data['favoriteGenreTags'] ?? []);

        // Load favorite books from Firebase
        final booksSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('books')
            .where('isFavorite', isEqualTo: true)
            .get();

        final newFavoriteBooks = booksSnapshot.docs
            .map((doc) => {
                  ...doc.data(),
                  'id': doc.id,
                })
            .where((book) =>
                book['listId'] != null) // Filter books that are in a list
            .toList();

        // Compare with local data and update if needed
        if (newTotalBooks != _totalBooks ||
            newTotalPages != _totalPages ||
            newFavoriteGenre != _favoriteGenre ||
            newFavoriteAuthor != _favoriteAuthor ||
            newLastUpdated != _lastUpdated ||
            !_areListsEqual(newFavoriteGenreTags, _favoriteGenreTags) ||
            !_areBookListsEqual(newFavoriteBooks, _favoriteBooks)) {
          setState(() {
            _totalBooks = newTotalBooks;
            _totalPages = newTotalPages;
            _favoriteGenre = newFavoriteGenre;
            _favoriteAuthor = newFavoriteAuthor;
            _lastUpdated = newLastUpdated;
            _favoriteGenreTags = newFavoriteGenreTags;
            _selectedGenres.clear();
            _selectedGenres.addAll(newFavoriteGenreTags);
            _favoriteBooks = newFavoriteBooks;
          });

          needsUpdate = true;
        }

        // Save to local storage if updates were needed
        if (needsUpdate) {
          await _saveProfileData();
        }
      }
    } catch (e) {
      print('Error syncing with Firebase: $e');
    }
  }

  bool _areListsEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  bool _areBookListsEqual(
      List<Map<String, dynamic>> list1, List<Map<String, dynamic>> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i]['id'] != list2[i]['id']) return false;
    }
    return true;
  }

  Future<void> _loadCachedData() async {
    print('Loading cached profile data');
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Use user-specific keys for caching
    final userPrefix = 'user_${user.uid}_';

    // Load cached image
    final cachedImage = prefs.getString('${userPrefix}cachedProfileImage');
    final lastUpdate = prefs.getInt('${userPrefix}lastImageUpdate');

    if (cachedImage != null && lastUpdate != null) {
      print('Found cached image');
      final lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(lastUpdate);
      final timeDifference =
          DateTime.now().difference(lastUpdateTime).inMinutes;

      print('Cache age: $timeDifference minutes');
      if (mounted) {
        setState(() {
          _base64Image = cachedImage;
        });
      }
    } else {
      print('No cached image found');
    }

    // Load book statistics with user-specific keys
    final totalBooks = prefs.getInt('${userPrefix}totalBooks') ?? 0;
    final totalPages = prefs.getInt('${userPrefix}totalPages') ?? 0;
    final favoriteGenre = prefs.getString('${userPrefix}favoriteGenre') ?? '';
    final favoriteAuthor = prefs.getString('${userPrefix}favoriteAuthor') ?? '';
    final lastUpdated = prefs.getString('${userPrefix}statsLastUpdated') ?? '';

    // Load favorite books from local cache with user-specific key
    final favoriteBooksJson =
        prefs.getString('${userPrefix}favoriteBooks') ?? '[]';
    final List<dynamic> favoriteBooksList = jsonDecode(favoriteBooksJson);
    _favoriteBooks = favoriteBooksList
        .map((book) => Map<String, dynamic>.from(book))
        .where((book) => book['listId'] != null)
        .toList();

    // Load username with user-specific key
    final username = prefs.getString('${userPrefix}username') ?? '';

    // Load birthday with user-specific key
    final birthdayStr = prefs.getString('${userPrefix}birthday');
    final birthday = birthdayStr != null ? DateTime.parse(birthdayStr) : null;

    // Load about me section with user-specific key
    final aboutMe = prefs.getString('${userPrefix}bio') ?? '';

    // Load favorite genre tags with user-specific key
    final genreTags =
        prefs.getStringList('${userPrefix}favoriteGenreTags') ?? [];

    if (mounted) {
      setState(() {
        _totalBooks = totalBooks;
        _totalPages = totalPages;
        _favoriteGenre = favoriteGenre;
        _favoriteAuthor = favoriteAuthor;
        _lastUpdated = lastUpdated;
        _username = username;
        _birthday = birthday;
        _aboutMe = aboutMe;
        _bioController.text = aboutMe;
        _favoriteGenreTags = genreTags;
        _selectedGenres.clear();
        _selectedGenres.addAll(genreTags);
      });
    }
  }

  Future<void> _saveProfileData() async {
    print('Saving profile data to local storage');
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Use user-specific keys for caching
    final userPrefix = 'user_${user.uid}_';

    // Save book statistics with user-specific keys
    await prefs.setInt('${userPrefix}totalBooks', _totalBooks);
    await prefs.setInt('${userPrefix}totalPages', _totalPages);
    await prefs.setString('${userPrefix}favoriteGenre', _favoriteGenre);
    await prefs.setString('${userPrefix}favoriteAuthor', _favoriteAuthor);
    await prefs.setString('${userPrefix}statsLastUpdated', _lastUpdated);

    // Save about me section with user-specific key
    await prefs.setString('${userPrefix}bio', _bioController.text);

    // Save favorite genre tags with user-specific key
    await prefs.setStringList(
        '${userPrefix}favoriteGenreTags', _selectedGenres);

    // Save favorite books with user-specific key
    await prefs.setString(
        '${userPrefix}favoriteBooks', jsonEncode(_favoriteBooks));

    // Save username with user-specific key
    await prefs.setString('${userPrefix}username', _username);

    // Save birthday with user-specific key
    if (_birthday != null) {
      await prefs.setString(
          '${userPrefix}birthday', _birthday!.toIso8601String());
    }

    // Save profile image with user-specific key
    if (_base64Image != null) {
      await prefs.setString('${userPrefix}cachedProfileImage', _base64Image!);
      await prefs.setInt('${userPrefix}lastImageUpdate',
          DateTime.now().millisecondsSinceEpoch);
    }

    print('Profile data saved successfully');
  }

  Future<void> _loadFromFirebase() async {
    print('Loading profile data from Firebase');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('No authenticated user found');
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final newBase64Image = data['profileImageBase64'];

        if (newBase64Image != null && newBase64Image != _base64Image) {
          print('New image found in Firebase, caching it');
          await _cacheProfileImage(newBase64Image);
          if (mounted) {
            setState(() {
              _base64Image = newBase64Image;
            });
          }
        }

        // Load other data from Firebase
        if (mounted) {
          setState(() {
            _totalBooks = data['totalBooks'] ?? 0;
            _totalPages = data['totalPages'] ?? 0;
            _favoriteGenre = data['favoriteGenre'] ?? '';
            _favoriteAuthor = data['favoriteAuthor'] ?? '';
            _lastUpdated = data['lastUpdated'] ?? '';
            _aboutMe = data['bio'] ?? '';
            _favoriteGenreTags =
                List<String>.from(data['favoriteGenreTags'] ?? []);
          });
        }
      }
    } catch (e) {
      print('Error loading from Firebase: $e');
    }
  }

  Future<void> _cacheProfileImage(String base64Image) async {
    print('Caching profile image');
    final prefs = await SharedPreferences.getInstance();
    try {
      await prefs.setString('cachedProfileImage', base64Image);
      await prefs.setInt(
          'lastImageUpdate', DateTime.now().millisecondsSinceEpoch);
      print('Successfully cached profile image');
      print('Image length: ${base64Image.length} bytes');
      print('Cache timestamp: ${DateTime.now()}');
    } catch (e) {
      print('Error caching image: $e');
    }
  }

  Future<void> _loadBookStats() async {
    final settings = app_settings.Settings();
    await settings.load();

    setState(() {
      _totalBooks = settings.totalBooks;
      _totalPages = settings.readBooks;
    });
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        // Check if the file exists and is readable
        final file = File(pickedFile.path);
        if (await file.exists()) {
          // Verify file size
          final fileSize = await file.length();
          if (fileSize > 2 * 1024 * 1024) {
            // 2MB limit for base64
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Image size must be less than 2MB')),
              );
            }
            return;
          }

          setState(() {
            _imageFile = file;
          });
          await _convertAndSaveImage();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Selected file is not accessible')),
            );
          }
        }
      }
    } on PlatformException catch (e) {
      print('Platform error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: ${e.message}')),
        );
      }
    } catch (e) {
      print('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error picking image. Please try again.')),
        );
      }
    }
  }

  Future<void> _convertAndSaveImage() async {
    if (_imageFile == null) return;

    try {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Processing image...')),
        );
      }

      // Convert image to base64
      final bytes = await _imageFile!.readAsBytes();
      final base64String = base64Encode(bytes);

      // Cache the image
      await _cacheProfileImage(base64String);

      if (mounted) {
        setState(() {
          _base64Image = base64String;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile image updated successfully')),
        );
      }
    } catch (e) {
      print('Error processing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error processing image. Please try again.')),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Save to local storage first
    await _saveProfileData();

    // Then sync with Firebase
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'bio': _bioController.text,
        'favoriteGenres': _selectedGenres,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error saving to Firebase: $e');
    }

    setState(() {
      _isEditing = false;
    });
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pop(context);
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        // Save data when exiting edit mode
        _saveProfileData();
      }
    });
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Show confirmation dialog
      final shouldDelete = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Account'),
          content: const Text(
              'Are you sure you want to delete your account? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );

      if (shouldDelete != true) return;

      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleting account...')),
        );
      }

      // Delete user data from Firestore
      final batch = FirebaseFirestore.instance.batch();

      // Delete user document
      batch
          .delete(FirebaseFirestore.instance.collection('users').doc(user.uid));

      // Delete user's books
      final booksSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('books')
          .get();
      for (var doc in booksSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // Delete user's lists
      final listsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('lists')
          .get();
      for (var doc in listsSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // Commit the batch
      await batch.commit();

      // Clear local storage for this user
      final prefs = await SharedPreferences.getInstance();
      final userPrefix = 'user_${user.uid}_';
      final keys = prefs.getKeys();
      for (var key in keys) {
        if (key.startsWith(userPrefix)) {
          await prefs.remove(key);
        }
      }

      // Delete the user account
      await user.delete();

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      print('Error deleting account: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting account: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    print(
        'build: isLoading: $_isLoading, hasImage: ${_base64Image != null}, isInitialized: $_isInitialized');

    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final user = FirebaseAuth.instance.currentUser;
    final percentage =
        _totalBooks > 0 ? (_totalPages / _totalBooks * 100).round() : 0;

    // Calculate account age
    final accountCreationTime = user?.metadata.creationTime;
    final accountAge = accountCreationTime != null
        ? DateTime.now().difference(accountCreationTime)
        : const Duration();
    final days = accountAge.inDays;
    final hours = accountAge.inHours % 24;
    final minutes = accountAge.inMinutes % 60;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _toggleEditMode();
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(
                      _isEditing ? Icons.save : Icons.edit,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(_isEditing ? 'Save' : 'Edit'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 16.0),
        child: Form(
          key: _formKey,
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
                      _buildProfileHeader(),
                      const SizedBox(height: 16),
                      // About Me Section
                      Text(
                        'About Me',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _bioController,
                        maxLines: 3,
                        enabled: _isEditing,
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: InputDecoration(
                          hintText: 'Write something about yourself...',
                          hintStyle: Theme.of(context).textTheme.bodySmall,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
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
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: _favoriteBooks.isEmpty
                            ? Center(
                                child: Text(
                                  'No favorite books yet',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              )
                            : ListView.builder(
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
                                            borderRadius:
                                                BorderRadius.circular(8),
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
                                              ? const Icon(
                                                  Icons.book,
                                                  size: 48,
                                                  color: Colors.grey,
                                                )
                                              : null,
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: 120,
                                          child: Tooltip(
                                            message: book['title'] ??
                                                'Unknown Title',
                                            child: Text(
                                              book['title'] ?? 'Unknown Title',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                    fontSize: Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium!
                                                            .fontSize! *
                                                        0.85,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                            ),
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
                          _buildStatColumn(
                              'Total Books', _totalBooks.toString()),
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
                        if (_isEditing) ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  decoration: InputDecoration(
                                    hintText: 'Add custom genre...',
                                    hintStyle:
                                        Theme.of(context).textTheme.bodySmall,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onFieldSubmitted: (value) {
                                    if (value.trim().isNotEmpty &&
                                        !_availableGenres
                                            .contains(value.trim())) {
                                      setState(() {
                                        _availableGenres.add(value.trim());
                                        _selectedGenres.add(value.trim());
                                      });
                                    }
                                  },
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add),
                                onPressed: () {
                                  final controller = TextEditingController();
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text('Add Custom Genre',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      content: TextField(
                                        controller: controller,
                                        decoration: InputDecoration(
                                          hintText: 'Enter genre name',
                                          hintStyle: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: Text('Cancel',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            final genre =
                                                controller.text.trim();
                                            if (genre.isNotEmpty &&
                                                !_availableGenres
                                                    .contains(genre)) {
                                              setState(() {
                                                _availableGenres.add(genre);
                                                _selectedGenres.add(genre);
                                              });
                                            }
                                            Navigator.pop(context);
                                          },
                                          child: Text('Add',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyMedium),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _availableGenres.map((genre) {
                            final isSelected = _selectedGenres.contains(genre);
                            return FilterChip(
                              label: Text(genre,
                                  style:
                                      Theme.of(context).textTheme.bodyMedium),
                              selected: isSelected,
                              onSelected: _isEditing
                                  ? (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedGenres.add(genre);
                                        } else {
                                          _selectedGenres.remove(genre);
                                        }
                                      });
                                    }
                                  : null,
                              deleteIcon: _isEditing
                                  ? const Icon(Icons.close, size: 18)
                                  : null,
                              onDeleted: _isEditing
                                  ? () {
                                      setState(() {
                                        _availableGenres.remove(genre);
                                        _selectedGenres.remove(genre);
                                      });
                                    }
                                  : null,
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
      ),
    );
  }

  Widget _buildProfileHeader() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    // Calculate account age
    final accountAge = user.metadata.creationTime != null
        ? DateTime.now().difference(user.metadata.creationTime!)
        : const Duration();
    final days = accountAge.inDays;
    final hours = accountAge.inHours % 24;
    final minutes = accountAge.inMinutes % 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _isEditing ? _pickImage : null,
              child: Stack(
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
                  if (_isEditing)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@$_username',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontSize: Theme.of(context)
                                  .textTheme
                                  .headlineSmall!
                                  .fontSize! *
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

  Widget _buildBookStats() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Book Statistics',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatItem('Total Books', _totalBooks.toString()),
                _buildStatItem('Total Pages', _totalPages.toString()),
              ],
            ),
            const SizedBox(height: 16),
            if (_favoriteGenre.isNotEmpty)
              _buildStatItem('Favorite Genre', _favoriteGenre),
            if (_favoriteAuthor.isNotEmpty)
              _buildStatItem('Favorite Author', _favoriteAuthor),
            if (_lastUpdated.isNotEmpty)
              _buildStatItem('Last Updated', _lastUpdated),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}
