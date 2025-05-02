import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final Color initialAccentColor;
  final Function(Color) onAccentColorChanged;

  const SettingsScreen({
    super.key,
    required this.onThemeChanged,
    required this.initialAccentColor,
    required this.onAccentColorChanged,
  });

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _followSystemTheme;
  late bool _useDarkMode;
  late Color _accentColor;
  late String _sortPreference;

  @override
  void initState() {
    super.initState();
    _followSystemTheme = true;
    _useDarkMode = false;
    _accentColor = widget.initialAccentColor;
    _sortPreference = 'title'; // Default sorting
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _followSystemTheme = prefs.getBool('followSystemTheme') ?? true;
        _useDarkMode = prefs.getBool('useDarkMode') ?? false;
        final savedColor = prefs.getInt('accentColor');
        _accentColor =
            savedColor != null ? Color(savedColor) : widget.initialAccentColor;
        _sortPreference = prefs.getString('sortPreference') ?? 'title';
      });
    }
    _notifyThemeChange();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('followSystemTheme', _followSystemTheme);
    await prefs.setBool('useDarkMode', _useDarkMode);
    await prefs.setInt('accentColor', _accentColor.value);
    await prefs.setString('sortPreference', _sortPreference);
    widget.onAccentColorChanged(_accentColor);
  }

  void _notifyThemeChange() {
    ThemeMode themeMode;
    if (_followSystemTheme) {
      themeMode = ThemeMode.system;
    } else {
      themeMode = _useDarkMode ? ThemeMode.dark : ThemeMode.light;
    }
    widget.onThemeChanged(themeMode);
  }

  void _showColorPickerDialog() {
    Color pickerColor = _accentColor;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pick Accent Color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: pickerColor,
            onColorChanged: (color) {
              pickerColor = color;
            },
            availableColors: [
              Colors.red,
              Colors.pink,
              Colors.purple,
              Colors.blue,
              Colors.cyan,
              Colors.teal,
              Colors.green,
              Colors.yellow,
              Colors.orange,
              Colors.brown,
            ]
                .map((color) => [
                      color.shade300,
                      color.shade500,
                      color.shade700,
                    ])
                .expand((shades) => shades)
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (mounted) {
                setState(() {
                  _accentColor = pickerColor;
                });
                _saveSettings();
              }
              Navigator.pop(context);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account and Data'),
        content: const Text(
          'Are you sure you want to permanently delete your account and all associated data? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmDelete == true && mounted) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          // Delete Firestore data
          final userDoc =
              FirebaseFirestore.instance.collection('users').doc(user.uid);
          final listsCollection = userDoc.collection('lists');
          final listsSnapshot = await listsCollection.get();

          for (var listDoc in listsSnapshot.docs) {
            // Delete books subcollection
            final booksCollection = listDoc.reference.collection('books');
            final booksSnapshot = await booksCollection.get();
            for (var bookDoc in booksSnapshot.docs) {
              await bookDoc.reference.delete();
            }
            // Delete list document
            await listDoc.reference.delete();
          }

          // Delete user document
          await userDoc.delete();

          // Clear shared preferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.clear();

          // Delete Firebase Auth account
          await user.delete();

          // Sign out
          await FirebaseAuth.instance.signOut();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Account and data deleted successfully')),
            );
            // Navigate to initial route (AuthScreen)
            Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting account: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Follow System Dark Mode'),
                        subtitle:
                            const Text('Use the device\'s dark mode setting'),
                        value: _followSystemTheme,
                        trackColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return _accentColor;
                          }
                          return null;
                        }),
                        onChanged: (value) {
                          if (mounted) {
                            setState(() {
                              _followSystemTheme = value;
                            });
                            _saveSettings();
                            _notifyThemeChange();
                          }
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Dark Mode'),
                        subtitle: const Text('Manually enable dark mode'),
                        value: _useDarkMode,
                        trackColor: WidgetStateProperty.resolveWith((states) {
                          if (states.contains(WidgetState.selected)) {
                            return _accentColor;
                          }
                          return null;
                        }),
                        onChanged: _followSystemTheme
                            ? null
                            : (value) {
                                if (mounted) {
                                  setState(() {
                                    _useDarkMode = value;
                                  });
                                  _saveSettings();
                                  _notifyThemeChange();
                                }
                              },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16.0),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    title: const Text('Accent Color'),
                    subtitle: const Text('Choose the app\'s accent color'),
                    trailing: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _accentColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey),
                      ),
                    ),
                    onTap: _showColorPickerDialog,
                  ),
                ),
                const SizedBox(height: 16.0),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        dropdownMenuTheme: DropdownMenuThemeData(
                          menuStyle: MenuStyle(
                            backgroundColor: MaterialStateProperty.all(
                              Theme.of(context).cardColor,
                            ),
                            elevation: MaterialStateProperty.all(2),
                            padding: MaterialStateProperty.all(
                              const EdgeInsets.symmetric(vertical: 8.0),
                            ),
                          ),
                        ),
                      ),
                      child: DropdownButtonFormField<String>(
                        value: _sortPreference,
                        decoration: InputDecoration(
                          labelText: 'Sort Books By',
                          labelStyle: TextStyle(
                            color: Theme.of(context).textTheme.bodyLarge?.color,
                          ),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8.0),
                        ),
                        dropdownColor: Theme.of(context).cardColor,
                        menuMaxHeight: 300,
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodyLarge?.color,
                        ),
                        selectedItemBuilder: (context) {
                          return const [
                            Text('Title'),
                            Text('Author'),
                            Text('Date Added'),
                            Text('Release Date'),
                          ];
                        },
                        items: [
                          _buildDropdownMenuItem('title', 'Title'),
                          _buildDropdownMenuItem('author', 'Author'),
                          _buildDropdownMenuItem('date_added', 'Date Added'),
                          _buildDropdownMenuItem(
                              'release_date', 'Release Date'),
                        ],
                        onChanged: (value) {
                          if (value != null && mounted) {
                            setState(() {
                              _sortPreference = value;
                            });
                            _saveSettings();
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(29.0, 16.0, 29.0, 31.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _deleteAccount,
              child: const Text('Delete My Account and Data'),
            ),
          ),
        ],
      ),
    );
  }

  DropdownMenuItem<String> _buildDropdownMenuItem(String value, String text) {
    return DropdownMenuItem<String>(
      value: value,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
        child: Text(
          text,
          style: TextStyle(
            color: Theme.of(context).textTheme.bodyLarge?.color,
          ),
        ),
      ),
    );
  }
}
