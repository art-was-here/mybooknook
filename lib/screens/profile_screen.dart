import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  @override
  void initState() {
    super.initState();
    print('initState: Starting profile load');
    _initializeData().then((_) {
      // Show debug popup after initialization
      _showDebugPopup();
    });
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

    print('DEBUG: -------- Profile Loading Process Completed --------');

    if (mounted) {
      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadCachedData() async {
    print('Loading cached profile data');
    final prefs = await SharedPreferences.getInstance();

    // Load cached image
    final cachedImage = prefs.getString('cachedProfileImage');
    final lastUpdate = prefs.getInt('lastImageUpdate');

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

    // Load book statistics
    final totalBooks = prefs.getInt('totalBooks') ?? 0;
    final totalPages = prefs.getInt('totalPages') ?? 0;
    final favoriteGenre = prefs.getString('favoriteGenre') ?? '';
    final favoriteAuthor = prefs.getString('favoriteAuthor') ?? '';
    final lastUpdated = prefs.getString('statsLastUpdated') ?? '';

    // Load favorite books
    final favoriteBooksJson = prefs.getString('favoriteBooks') ?? '[]';
    final List<dynamic> favoriteBooksList = jsonDecode(favoriteBooksJson);
    _favoriteBooks = favoriteBooksList
        .map((book) => Map<String, dynamic>.from(book))
        .toList();

    if (mounted) {
      setState(() {
        _totalBooks = totalBooks;
        _totalPages = totalPages;
        _favoriteGenre = favoriteGenre;
        _favoriteAuthor = favoriteAuthor;
        _lastUpdated = lastUpdated;
      });
    }

    // Load about me section
    final aboutMe = prefs.getString('aboutMe') ?? '';
    if (mounted) {
      setState(() {
        _aboutMe = aboutMe;
        _bioController.text = aboutMe;
      });
    }

    // Load favorite genre tags
    final genreTags = prefs.getStringList('favoriteGenreTags') ?? [];
    if (mounted) {
      setState(() {
        _favoriteGenreTags = genreTags;
        _selectedGenres.clear();
        _selectedGenres.addAll(genreTags);
      });
    }
  }

  Future<void> _saveProfileData() async {
    print('Saving profile data to local storage');
    final prefs = await SharedPreferences.getInstance();

    // Save book statistics
    await prefs.setInt('totalBooks', _totalBooks);
    await prefs.setInt('totalPages', _totalPages);
    await prefs.setString('favoriteGenre', _favoriteGenre);
    await prefs.setString('favoriteAuthor', _favoriteAuthor);
    await prefs.setString('statsLastUpdated', _lastUpdated);

    // Save about me section
    await prefs.setString('aboutMe', _bioController.text);

    // Save favorite genre tags
    await prefs.setStringList('favoriteGenreTags', _selectedGenres);

    // Save favorite books
    await prefs.setString('favoriteBooks', jsonEncode(_favoriteBooks));

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
            _aboutMe = data['aboutMe'] ?? '';
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

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'bio': _bioController.text,
      'favoriteGenres': _selectedGenres,
    });

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

  Future<void> _showDebugPopup() async {
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final cachedImage = prefs.getString('cachedProfileImage');
    final lastUpdate = prefs.getInt('lastImageUpdate');
    final lastUpdateTime = lastUpdate != null
        ? DateTime.fromMillisecondsSinceEpoch(lastUpdate)
        : null;
    final timeDifference = lastUpdateTime != null
        ? DateTime.now().difference(lastUpdateTime).inMinutes
        : null;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Debug Info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Cached Image Exists: ${cachedImage != null}'),
              if (lastUpdateTime != null) ...[
                Text('Last Update: $lastUpdateTime'),
                Text('Age: $timeDifference minutes'),
                Text('Image Length: ${cachedImage?.length ?? 0} bytes'),
              ],
              if (cachedImage != null) ...[
                const SizedBox(height: 16),
                const Text('Cached Image Preview:'),
                const SizedBox(height: 8),
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(
                      image: MemoryImage(base64Decode(cachedImage)),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ],
          ),
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

  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        // Save data when exiting edit mode
        _saveProfileData();
      }
    });
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
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _showLogoutDialog,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Info Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Profile Photo
                          Container(
                            width: 96, // 20% smaller than original 120
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              image: _base64Image != null
                                  ? DecorationImage(
                                      image: MemoryImage(
                                          base64Decode(_base64Image!)),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              color: Colors.grey[200],
                            ),
                            child: _base64Image == null
                                ? const Icon(
                                    Icons.person,
                                    size: 48,
                                    color: Colors.grey,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          // Username and Account Age
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '@${user?.displayName ?? 'user'}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontSize: Theme.of(context)
                                                .textTheme
                                                .titleLarge!
                                                .fontSize! *
                                            0.9,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Account age: $days days, $hours hours, $minutes minutes',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
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
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Favorites Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
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
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Book Statistics',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          TextButton(
                            onPressed: _toggleEditMode,
                            child: Text(_isEditing ? 'Save' : 'Edit'),
                          ),
                        ],
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
                child: Padding(
                  padding: const EdgeInsets.all(16),
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
                                        onPressed: () => Navigator.pop(context),
                                        child: Text('Cancel',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          final genre = controller.text.trim();
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
                                style: Theme.of(context).textTheme.bodyMedium),
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
            ],
          ),
        ),
      ),
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
        padding: const EdgeInsets.all(16.0),
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
