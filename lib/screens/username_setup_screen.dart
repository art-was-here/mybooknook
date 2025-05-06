import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';

class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({super.key});

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  DateTime? _selectedDate;
  bool _isLoading = false;
  String? _errorMessage;
  File? _imageFile;
  String? _base64Image;
  String? _bio;
  DateTime? _lastBackPress;

  // Birthday selection variables
  int? _selectedDay;
  int? _selectedMonth;
  int? _selectedYear;
  final List<int> _days = List.generate(31, (index) => index + 1);
  final List<int> _months = List.generate(12, (index) => index + 1);
  final List<int> _years = List.generate(
      DateTime.now().year - 1900 + 1, (index) => DateTime.now().year - index);

  Future<bool> _checkUsernameAvailability(String username) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username.toLowerCase())
        .get();
    return snapshot.docs.isEmpty;
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
        final file = File(pickedFile.path);
        if (await file.exists()) {
          final fileSize = await file.length();
          if (fileSize > 2 * 1024 * 1024) {
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
        }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Processing image...')),
        );
      }

      final bytes = await _imageFile!.readAsBytes();
      final base64String = base64Encode(bytes);

      setState(() {
        _base64Image = base64String;
      });
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

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final username = _usernameController.text.trim();
      final isAvailable = await _checkUsernameAvailability(username);

      if (!isAvailable) {
        setState(() {
          _errorMessage = 'This username is already taken';
          _isLoading = false;
        });
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _errorMessage = 'User not found';
          _isLoading = false;
        });
        return;
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'username': username.toLowerCase(),
        'displayName': username,
        'birthday': _selectedDate,
        'createdAt': FieldValue.serverTimestamp(),
        'setupComplete': true,
        if (_base64Image != null) 'profileImageBase64': _base64Image,
        if (_bio != null) 'bio': _bio,
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'An error occurred: $e';
        _isLoading = false;
      });
    }
  }

  void _updateSelectedDate() {
    if (_selectedDay != null &&
        _selectedMonth != null &&
        _selectedYear != null) {
      setState(() {
        _selectedDate =
            DateTime(_selectedYear!, _selectedMonth!, _selectedDay!);
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final now = DateTime.now();
        if (_lastBackPress == null ||
            now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
          _lastBackPress = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Swipe back again to exit'),
              duration: Duration(seconds: 2),
            ),
          );
          return false;
        }
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Complete Your Profile'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final now = DateTime.now();
              if (_lastBackPress == null ||
                  now.difference(_lastBackPress!) >
                      const Duration(seconds: 2)) {
                _lastBackPress = now;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Press back again to exit'),
                    duration: Duration(seconds: 2),
                  ),
                );
                return;
              }
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 0.0),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 5.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Profile Photo and Username Display Section
                        Padding(
                          padding: const EdgeInsets.only(left: 10.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Stack(
                                children: [
                                  CircleAvatar(
                                    radius: 48,
                                    backgroundImage: _base64Image != null
                                        ? MemoryImage(
                                            base64Decode(_base64Image!))
                                        : null,
                                    child: _base64Image == null
                                        ? const Icon(Icons.person, size: 48)
                                        : null,
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButton(
                                        icon: const Icon(Icons.camera_alt,
                                            color: Colors.white, size: 20),
                                        onPressed: _pickImage,
                                        tooltip: 'Add profile photo',
                                        padding: const EdgeInsets.all(8),
                                        constraints: const BoxConstraints(
                                          minWidth: 32,
                                          minHeight: 32,
                                        ),
                                      ),
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
                                      _usernameController.text.isEmpty
                                          ? '@username'
                                          : '@${_usernameController.text.toLowerCase()}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            color:
                                                _usernameController.text.isEmpty
                                                    ? Colors.grey
                                                    : Theme.of(context)
                                                        .colorScheme
                                                        .primary,
                                            fontSize: Theme.of(context)
                                                    .textTheme
                                                    .headlineSmall!
                                                    .fontSize! *
                                                0.9,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Account Age: Finish signing up to get started!',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Colors.grey[600],
                                            fontSize: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall!
                                                    .fontSize! *
                                                1.05,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Username Field
                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            hintText: 'Choose a unique username (max 15 chars)',
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a username';
                            }
                            if (value.length > 15) {
                              return 'Username must be 15 characters or less';
                            }
                            if (!RegExp(r'^[a-zA-Z0-9\-_\.]+$')
                                .hasMatch(value)) {
                              return 'Username can only contain letters, numbers, -, _, and .';
                            }
                            return null;
                          },
                          onChanged: (value) {
                            setState(
                                () {}); // Trigger rebuild to update the display
                          },
                        ),
                        const SizedBox(height: 16),
                        // Birthday Selection
                        Text(
                          'Birthday (Optional)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Month Dropdown
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _selectedMonth,
                                decoration: const InputDecoration(
                                  labelText: 'Month',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                items: _months.map((month) {
                                  return DropdownMenuItem(
                                    value: month,
                                    child: Text(
                                      DateFormat('MMMM')
                                          .format(DateTime(2000, month)),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedMonth = value;
                                    _updateSelectedDate();
                                  });
                                },
                                icon: const SizedBox.shrink(),
                                isExpanded: true,
                                dropdownColor: Theme.of(context).cardColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Day Dropdown
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _selectedDay,
                                decoration: const InputDecoration(
                                  labelText: 'Day',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                items: _days.map((day) {
                                  return DropdownMenuItem(
                                    value: day,
                                    child: Text(
                                      day.toString(),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedDay = value;
                                    _updateSelectedDate();
                                  });
                                },
                                icon: const SizedBox.shrink(),
                                isExpanded: true,
                                dropdownColor: Theme.of(context).cardColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Year Dropdown
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                value: _selectedYear,
                                decoration: const InputDecoration(
                                  labelText: 'Year',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                items: _years.map((year) {
                                  return DropdownMenuItem(
                                    value: year,
                                    child: Text(
                                      year.toString(),
                                      textAlign: TextAlign.center,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedYear = value;
                                    _updateSelectedDate();
                                  });
                                },
                                icon: const SizedBox.shrink(),
                                isExpanded: true,
                                dropdownColor: Theme.of(context).cardColor,
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                              left: 16.0, bottom: 16.0, top: 8.0),
                          child: Text(
                            'Your birthday will not be shown on your profile',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[600],
                                    ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Bio Section
                        Text(
                          'About Me (Optional)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Tell us a little about yourself...',
                            hintStyle: Theme.of(context).textTheme.bodySmall,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding:
                                const EdgeInsets.fromLTRB(12, 12, 12, 17),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _bio = value;
                            });
                          },
                        ),
                        const SizedBox(height: 5),
                        if (_errorMessage != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
