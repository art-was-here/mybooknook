import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'dart:convert';
import '../models/settings.dart' as app_settings;
import '../models/book.dart';
import '../services/notification_service.dart';
import '../services/update_service.dart';
import '../main.dart';

class SettingsScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final Function(Color) onAccentColorChanged;
  final Function(String) onSortOrderChanged;
  final Color accentColor;
  final Function(bool)? onMaterialYouChanged;

  const SettingsScreen({
    super.key,
    required this.onThemeChanged,
    required this.onAccentColorChanged,
    required this.onSortOrderChanged,
    required this.accentColor,
    this.onMaterialYouChanged,
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
  bool _useMaterialYou = false;
  final NotificationService _notificationService = NotificationService();
  final UpdateService _updateService = UpdateService(
    owner: 'your-github-username', // Replace with your GitHub username
    repo: 'mybooknook', // Replace with your repo name
  );
  bool _isCheckingUpdate = false;
  bool _isTestingNotification = false;
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;
  bool _dynamicColorsAvailable = false;

  @override
  void initState() {
    super.initState();
    _selectedAccentColor = widget.accentColor;
    _loadSettings();
    _scrollController.addListener(_handleScroll);
    _checkDynamicColorSupport();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.offset > 0 && !_isScrolled) {
      setState(() {
        _isScrolled = true;
      });
    } else if (_scrollController.offset <= 0 && _isScrolled) {
      setState(() {
        _isScrolled = false;
      });
    }
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
          _useMaterialYou = _settings.useMaterialYou;
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
          SnackBar(
            content: Text('Exported ${books.length} books'),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting books: $e'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _importBooks() async {
    // TODO: Implement book import functionality
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Import functionality coming soon!'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          behavior: SnackBarBehavior.floating,
        ),
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
          SnackBar(
            content: const Text('Account deleted successfully'),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pushReplacementNamed('/');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting account: $e'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _checkDynamicColorSupport() {
    try {
      // We can't easily check if dynamic colors are available at runtime
      // So initially we'll assume they are, and let the UI in main.dart
      // determine if they're actually being applied
      setState(() {
        _dynamicColorsAvailable = true;
      });

      // We'll update this value when we get the first build with theme data
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final dynamicColorPrimary = Theme.of(context).colorScheme.primary;
        final userAccentColor = widget.accentColor;

        // If Material You is enabled and the primary color is different from the user's accent color,
        // then dynamic colors are likely being applied
        if (_useMaterialYou && dynamicColorPrimary != userAccentColor) {
          setState(() {
            _dynamicColorsAvailable = true;
          });
          print('Dynamic colors confirmed: primary=${dynamicColorPrimary}');
        } else if (_useMaterialYou) {
          // If Material You is enabled but the colors match the accent color,
          // dynamic colors may not be available
          print(
              'Dynamic colors may not be available: primary=${dynamicColorPrimary}, accent=${userAccentColor}');
        }
      });
    } catch (e) {
      print('Error checking dynamic color support: $e');
      setState(() {
        _dynamicColorsAvailable = false;
      });
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
        backgroundColor: _isScrolled
            ? Theme.of(context).colorScheme.primaryContainer
            : Colors.transparent,
        elevation: _isScrolled ? 4 : 0,
        foregroundColor: _isScrolled
            ? Theme.of(context).colorScheme.onPrimaryContainer
            : Theme.of(context).colorScheme.onBackground,
      ),
      body: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaleFactor: 0.85),
        child: ListView(
          controller: _scrollController,
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
                      subtitle: const Text(
                          'Make the app follow your system dark mode settings'),
                      trailing: Switch(
                        value: _themeMode == ThemeMode.system,
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
                      title: const Text('Dark Mode'),
                      subtitle: Text(_themeMode == ThemeMode.system
                          ? 'Disabled when following system dark mode'
                          : 'Manually control dark mode'),
                      trailing: Switch(
                        value: _themeMode == ThemeMode.dark,
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
                      title: Row(
                        children: [
                          const Text('Material You'),
                          if (_useMaterialYou)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                                size: 16,
                              ),
                            ),
                        ],
                      ),
                      subtitle: const Text(
                          'Use system accent colors from your device theme'),
                      trailing: Switch(
                        value: _useMaterialYou,
                        onChanged: (value) {
                          setState(() {
                            _useMaterialYou = value;
                          });
                          _settings.updateUseMaterialYou(value);
                          if (widget.onMaterialYouChanged != null) {
                            widget.onMaterialYouChanged!(value);
                          }
                        },
                      ),
                    ),
                    ListTile(
                      title: const Text('Accent Color'),
                      subtitle: _useMaterialYou
                          ? const Text('Disabled when Material You is enabled')
                          : const Text('Choose an accent color'),
                      trailing: _useMaterialYou
                          ? Icon(Icons.color_lens,
                              color: Theme.of(context).disabledColor)
                          : ColorPickerButton(
                              initialColor: _selectedAccentColor,
                              onColorSelected: (color) {
                                _saveAccentColor(color);
                              },
                            ),
                      enabled: !_useMaterialYou,
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
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
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
                      'Notifications',
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
                      title: const Text('Test Notification'),
                      subtitle: const Text(
                          'Send a test notification with a 5-second delay'),
                      trailing: _isTestingNotification
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.notifications_active),
                      onTap: _isTestingNotification
                          ? null
                          : () => _sendTestNotification(),
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
                      'App Updates',
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
                      title: const Text('Check for updates'),
                      subtitle:
                          const Text('Check if a new version is available'),
                      trailing: _isCheckingUpdate
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.system_update),
                      onTap: _isCheckingUpdate ? null : _checkForUpdates,
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

  void _saveAccentColor(Color color) {
    setState(() {
      _selectedAccentColor = color;
    });
    widget.onAccentColorChanged(color);
    _settings.updateAccentColor(color);
  }

  Future<void> _sendTestNotification() async {
    if (_isTestingNotification) return;

    setState(() {
      _isTestingNotification = true;
    });

    try {
      // Show a snackbar to inform the user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Test notification will appear in 5 seconds'),
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );

      // Send the test notification
      await _notificationService.sendTestNotification();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending test notification: $e'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTestingNotification = false;
        });
      }
    }
  }

  Future<void> _checkForUpdates() async {
    if (_isCheckingUpdate) return;

    setState(() {
      _isCheckingUpdate = true;
    });

    try {
      final release = await _updateService.checkForUpdates();

      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });

        if (release != null) {
          await _updateService.showUpdateDialog(context, release);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('You are using the latest version'),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingUpdate = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking for updates: $e'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            behavior: SnackBarBehavior.floating,
          ),
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
