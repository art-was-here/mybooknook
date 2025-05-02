import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final Color initialAccentColor;

  const SettingsScreen({
    super.key,
    required this.onThemeChanged,
    required this.initialAccentColor,
  });

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _followSystemTheme;
  late bool _useDarkMode;
  late Color _accentColor;

  @override
  void initState() {
    super.initState();
    _followSystemTheme = true; // Default: follow system theme
    _useDarkMode = false; // Default: light mode (overridden by system if _followSystemTheme is true)
    _accentColor = widget.initialAccentColor;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _followSystemTheme = prefs.getBool('followSystemTheme') ?? true;
      _useDarkMode = prefs.getBool('useDarkMode') ?? false;
      final savedColor = prefs.getInt('accentColor');
      _accentColor = savedColor != null ? Color(savedColor) : widget.initialAccentColor;
    });
    _notifyThemeChange();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('followSystemTheme', _followSystemTheme);
    await prefs.setBool('useDarkMode', _useDarkMode);
    await prefs.setInt('accentColor', _accentColor.value);
  }

  void _notifyThemeChange() {
    ThemeMode themeMode;
    if (_followSystemTheme) {
      // Will be handled by MaterialApp's themeMode: ThemeMode.system
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
            ].map((color) => [
                  color.shade300,
                  color.shade500,
                  color.shade700,
                ]).expand((shades) => shades).toList(),
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
              setState(() {
                _accentColor = pickerColor;
              });
              _saveSettings();
              Navigator.pop(context);
            },
            child: const Text('Select'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          SwitchListTile(
            title: const Text('Follow System Dark Mode'),
            subtitle: const Text('Use the device\'s dark mode setting'),
            value: _followSystemTheme,
            activeColor: _accentColor,
            onChanged: (value) {
              setState(() {
                _followSystemTheme = value;
              });
              _saveSettings();
              _notifyThemeChange();
            },
          ),
          SwitchListTile(
            title: const Text('Dark Mode'),
            subtitle: const Text('Manually enable dark mode'),
            value: _useDarkMode,
            activeColor: _accentColor,
            onChanged: _followSystemTheme
                ? null // Disabled if following system theme
                : (value) {
                    setState(() {
                      _useDarkMode = value;
                    });
                    _saveSettings();
                    _notifyThemeChange();
                  },
          ),
          ListTile(
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
        ],
      ),
    );
  }
}