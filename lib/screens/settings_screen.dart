import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import '../models/settings.dart' as app_settings;
import '../models/book.dart';

class SettingsScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final Function(Color) onAccentColorChanged;
  final Function(String) onSortOrderChanged;
  final Color accentColor;

  const SettingsScreen({
    super.key,
    required this.onThemeChanged,
    required this.onAccentColorChanged,
    required this.onSortOrderChanged,
    required this.accentColor,
  });

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late app_settings.Settings _settings;
  bool _isLoading = true;
  String? _errorMessage;
  ThemeMode _themeMode = ThemeMode.system;
  Color _selectedAccentColor = Colors.teal;
  String _sortOrder = 'title';
  Color _accentColor = Colors.teal;

  @override
  void initState() {
    super.initState();
    _selectedAccentColor = widget.accentColor;
    _loadSettings();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeMode = prefs.getString('themeMode') ?? 'system';
    setState(() {
      _themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.toString() == 'ThemeMode.$themeMode',
        orElse: () => ThemeMode.system,
      );
    });
  }

  Future<void> _saveThemeMode(ThemeMode mode) async {
    final settings = app_settings.Settings();
    await settings.load();
    await settings.updateThemeMode(mode);
    widget.onThemeChanged(mode);
  }

  Future<void> _loadSortOrder() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sortOrder = prefs.getString('sortOrder') ?? 'title';
    });
  }

  Future<void> _saveSortOrder(String order) async {
    final settings = app_settings.Settings();
    await settings.load();
    await settings.updateSortOrder(order);
    widget.onSortOrderChanged(order);
  }

  Future<void> _loadSettings() async {
    try {
      _settings = app_settings.Settings();
      await _settings.load();
      if (mounted) {
        setState(() {
          _themeMode = _settings.themeMode;
          _accentColor = _settings.accentColor;
          _selectedAccentColor = _settings.accentColor;
          _sortOrder = _settings.sortOrder;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading settings: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _exportBooks() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final booksSnapshot = await FirebaseFirestore.instance
          .collectionGroup('books')
          .where('userId', isEqualTo: user.uid)
          .get();

      final books = booksSnapshot.docs.map((doc) {
        final data = doc.data();
        return Book.fromMap(data);
      }).toList();

      final jsonData = json.encode(books.map((book) => book.toMap()).toList());

      await _settings.updateLastExportDate();
      await _settings.updateBookCounts(
          books.length, books.where((b) => b.isRead).length);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${books.length} books')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting books: $e')),
        );
      }
    }
  }

  Future<void> _importBooks() async {
    // TODO: Implement book import functionality
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import functionality coming soon!')),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // First, re-authenticate the user
      final credential =
          await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
      if (credential.user == null) {
        throw Exception('Re-authentication failed');
      }

      // Delete user data from Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();

      // Delete user account
      await user.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account deleted successfully')),
        );
        Navigator.of(context).pushReplacementNamed('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting account: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadSettings,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
      ),
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaleFactor: 0.85),
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 16.0),
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 5.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15.0),
                      child: const Divider(height: 1),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: const Text('Follow System Dark Mode'),
                      trailing: Switch(
                        value: _themeMode == ThemeMode.system,
                        activeColor: _accentColor,
                        onChanged: (value) {
                          setState(() {
                            _themeMode =
                                value ? ThemeMode.system : ThemeMode.light;
                          });
                          _saveThemeMode(_themeMode);
                        },
                      ),
                    ),
                    ListTile(
                      title: const Text('Dark Mode (Manual)'),
                      trailing: Switch(
                        value: _themeMode == ThemeMode.dark,
                        activeColor: _accentColor,
                        onChanged: _themeMode == ThemeMode.system
                            ? null
                            : (value) {
                                setState(() {
                                  _themeMode =
                                      value ? ThemeMode.dark : ThemeMode.light;
                                });
                                _saveThemeMode(_themeMode);
                              },
                      ),
                    ),
                    ListTile(
                      title: const Text('Accent Color'),
                      trailing: ColorPickerButton(
                        initialColor: _selectedAccentColor,
                        onColorSelected: (color) {
                          _saveAccentColor(color);
                        },
                      ),
                    ),
                    ListTile(
                      title: const Text('Book List Order'),
                      subtitle: DropdownButton<String>(
                        value: _sortOrder,
                        items: const [
                          DropdownMenuItem(
                            value: 'title',
                            child: Text('Title (A-Z)'),
                          ),
                          DropdownMenuItem(
                            value: 'title_desc',
                            child: Text('Title (Z-A)'),
                          ),
                          DropdownMenuItem(
                            value: 'author',
                            child: Text('Author (A-Z)'),
                          ),
                          DropdownMenuItem(
                            value: 'author_desc',
                            child: Text('Author (Z-A)'),
                          ),
                          DropdownMenuItem(
                            value: 'date_added',
                            child: Text('Date Added (Newest)'),
                          ),
                          DropdownMenuItem(
                            value: 'date_added_desc',
                            child: Text('Date Added (Oldest)'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _sortOrder = value;
                            });
                            _saveSortOrder(value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 5.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reading Statistics',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15.0),
                      child: const Divider(height: 1),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: const Text('Total Books'),
                      subtitle:
                          Text('${_settings.totalBooks} books in your library'),
                    ),
                    ListTile(
                      title: const Text('Books Read'),
                      subtitle: Text('${_settings.readBooks} books completed'),
                    ),
                    ListTile(
                      title: const Text('Reading Progress'),
                      subtitle: LinearProgressIndicator(
                        value: _settings.readingProgress / 100,
                        backgroundColor: _accentColor.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(_accentColor),
                      ),
                      trailing: Text(
                          '${_settings.readingProgress.toStringAsFixed(1)}%'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 10.0, 10.0, 5.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Data Management',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15.0),
                      child: const Divider(height: 1),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: const Text('Export Books'),
                      subtitle: Text(_settings.lastExportDate != null
                          ? 'Last exported: ${_settings.lastExportDate!.toLocal().toString()}'
                          : 'Never exported'),
                      trailing: const Icon(Icons.file_download),
                      onTap: _exportBooks,
                    ),
                    ListTile(
                      title: const Text('Import Books'),
                      subtitle: Text(_settings.lastImportDate != null
                          ? 'Last imported: ${_settings.lastImportDate!.toLocal().toString()}'
                          : 'Never imported'),
                      trailing: const Icon(Icons.file_upload),
                      onTap: _importBooks,
                    ),
                    ListTile(
                      title: const Text('Delete Account'),
                      subtitle: const Text(
                          'Permanently delete your account and all data'),
                      trailing:
                          const Icon(Icons.delete_forever, color: Colors.red),
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Account'),
                            content: const Text(
                                'Are you sure you want to delete your account? This action cannot be undone.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _deleteAccount();
                                },
                                child: const Text('Delete',
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAccentColor(Color color) async {
    try {
      await _settings.updateAccentColor(color);
      if (mounted) {
        setState(() {
          _accentColor = color;
          _selectedAccentColor = color;
        });
        widget.onAccentColorChanged(color);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving accent color: $e')),
        );
      }
    }
  }
}

class ColorPickerButton extends StatelessWidget {
  final Color initialColor;
  final Function(Color) onColorSelected;

  const ColorPickerButton({
    super.key,
    required this.initialColor,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Pick a color'),
            content: SingleChildScrollView(
              child: ColorPicker(
                initialColor: initialColor,
                onColorSelected: (color) {
                  Navigator.pop(context);
                  onColorSelected(color);
                },
              ),
            ),
          ),
        );
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: initialColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey),
        ),
      ),
    );
  }
}

class ColorPicker extends StatelessWidget {
  final Color initialColor;
  final Function(Color) onColorSelected;

  const ColorPicker({
    super.key,
    required this.initialColor,
    required this.onColorSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Colors.teal,
        Colors.blue,
        Colors.indigo,
        Colors.purple,
        Colors.pink,
        Colors.red,
        Colors.orange,
        Colors.amber,
        Colors.green,
        Colors.lightBlue,
        Colors.cyan,
        Colors.deepPurple,
        Colors.deepOrange,
        Colors.brown,
        Colors.grey,
      ].map((color) {
        return GestureDetector(
          onTap: () => onColorSelected(color),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: color == initialColor ? Colors.white : Colors.grey,
                width: color == initialColor ? 3 : 1,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
