import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class Settings {
  static const String _fontSizeKey = 'font_size';
  static const String _listDensityKey = 'list_density';
  static const String _lastExportDateKey = 'last_export_date';
  static const String _lastImportDateKey = 'last_import_date';
  static const String _totalBooksKey = 'total_books';
  static const String _readBooksKey = 'read_books';
  static const String _themeModeKey = 'theme_mode';
  static const String _accentColorKey = 'accent_color';
  static const String _sortOrderKey = 'sort_order';
  static const String _useMaterialYouKey = 'use_material_you';
  static const String _showBirthdayKey = 'show_birthday';

  double _fontSize = 1.0;
  String _listDensity = 'comfortable';
  DateTime? _lastExportDate;
  DateTime? _lastImportDate;
  int _totalBooks = 0;
  int _readBooks = 0;
  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = Colors.teal;
  String _sortOrder = 'title';
  bool _useMaterialYou = false;
  bool _showBirthday = false;

  // Getters
  double get fontSize => _fontSize;
  String get listDensity => _listDensity;
  DateTime? get lastExportDate => _lastExportDate;
  DateTime? get lastImportDate => _lastImportDate;
  int get totalBooks => _totalBooks;
  int get readBooks => _readBooks;
  ThemeMode get themeMode => _themeMode;
  Color get accentColor => _accentColor;
  String get sortOrder => _sortOrder;
  bool get useMaterialYou => _useMaterialYou;
  bool get showBirthday => _showBirthday;
  double get readingProgress =>
      _totalBooks > 0 ? (_readBooks / _totalBooks) * 100 : 0;

  // Load settings from SharedPreferences
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    _fontSize = prefs.getDouble(_fontSizeKey) ?? 1.0;
    _listDensity = prefs.getString(_listDensityKey) ?? 'comfortable';
    _lastExportDate = prefs.getString(_lastExportDateKey) != null
        ? DateTime.parse(prefs.getString(_lastExportDateKey)!)
        : null;
    _lastImportDate = prefs.getString(_lastImportDateKey) != null
        ? DateTime.parse(prefs.getString(_lastImportDateKey)!)
        : null;
    _totalBooks = prefs.getInt(_totalBooksKey) ?? 0;
    _readBooks = prefs.getInt(_readBooksKey) ?? 0;
    _themeMode = ThemeMode.values.firstWhere(
      (mode) =>
          mode.toString() ==
          'ThemeMode.${prefs.getString(_themeModeKey) ?? 'system'}',
      orElse: () => ThemeMode.system,
    );
    _accentColor = Color(prefs.getInt(_accentColorKey) ?? Colors.teal.value);
    _sortOrder = prefs.getString(_sortOrderKey) ?? 'title';
    _useMaterialYou = prefs.getBool(_useMaterialYouKey) ?? false;
    _showBirthday = prefs.getBool(_showBirthdayKey) ?? false;
  }

  // Save settings to SharedPreferences
  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble(_fontSizeKey, _fontSize);
    await prefs.setString(_listDensityKey, _listDensity);
    if (_lastExportDate != null) {
      await prefs.setString(
          _lastExportDateKey, _lastExportDate!.toIso8601String());
    }
    if (_lastImportDate != null) {
      await prefs.setString(
          _lastImportDateKey, _lastImportDate!.toIso8601String());
    }
    await prefs.setInt(_totalBooksKey, _totalBooks);
    await prefs.setInt(_readBooksKey, _readBooks);
    await prefs.setString(_themeModeKey, _themeMode.toString().split('.').last);
    await prefs.setInt(_accentColorKey, _accentColor.value);
    await prefs.setString(_sortOrderKey, _sortOrder);
    await prefs.setBool(_useMaterialYouKey, _useMaterialYou);
    await prefs.setBool(_showBirthdayKey, _showBirthday);
  }

  Future<void> initialize() async {
    // Load from local storage first
    await load();

    // Then sync with Firebase if needed
    await _syncWithFirebase();
  }

  Future<void> _syncWithFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('app_settings')
          .get();

      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        bool needsUpdate = false;

        // Check each setting and update if needed
        if (data['fontSize'] != _fontSize) {
          _fontSize = data['fontSize'] as double;
          needsUpdate = true;
        }
        if (data['listDensity'] != _listDensity) {
          _listDensity = data['listDensity'] as String;
          needsUpdate = true;
        }
        if (data['themeMode'] != _themeMode.toString().split('.').last) {
          _themeMode = ThemeMode.values.firstWhere(
            (mode) => mode.toString() == 'ThemeMode.${data['themeMode']}',
            orElse: () => ThemeMode.system,
          );
          needsUpdate = true;
        }
        if (data['accentColor'] != _accentColor.value) {
          _accentColor = Color(data['accentColor'] as int);
          needsUpdate = true;
        }
        if (data['sortOrder'] != _sortOrder) {
          _sortOrder = data['sortOrder'] as String;
          needsUpdate = true;
        }
        if (data.containsKey('useMaterialYou') &&
            data['useMaterialYou'] != _useMaterialYou) {
          _useMaterialYou = data['useMaterialYou'] as bool;
          needsUpdate = true;
        }
        if (data.containsKey('showBirthday') &&
            data['showBirthday'] != _showBirthday) {
          _showBirthday = data['showBirthday'] as bool;
          needsUpdate = true;
        }

        // Save to local storage if updates were needed
        if (needsUpdate) {
          await save();
        }
      }
    } catch (e) {
      print('Error syncing settings with Firebase: $e');
    }
  }

  Future<void> saveToFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('app_settings')
          .set({
        'fontSize': _fontSize,
        'listDensity': _listDensity,
        'themeMode': _themeMode.toString().split('.').last,
        'accentColor': _accentColor.value,
        'sortOrder': _sortOrder,
        'useMaterialYou': _useMaterialYou,
        'showBirthday': _showBirthday,
        'lastUpdated': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error saving settings to Firebase: $e');
    }
  }

  // Update methods to include Firebase sync
  Future<void> updateFontSize(double size) async {
    _fontSize = size;
    await save();
    await saveToFirebase();
  }

  Future<void> updateListDensity(String density) async {
    _listDensity = density;
    await save();
    await saveToFirebase();
  }

  Future<void> updateLastExportDate() async {
    _lastExportDate = DateTime.now();
    await save();
  }

  Future<void> updateLastImportDate() async {
    _lastImportDate = DateTime.now();
    await save();
  }

  Future<void> updateBookCounts(int total, int read) async {
    _totalBooks = total;
    _readBooks = read;
    await save();
  }

  Future<void> incrementReadBooks() async {
    _readBooks++;
    await save();
  }

  Future<void> decrementReadBooks() async {
    if (_readBooks > 0) {
      _readBooks--;
      await save();
    }
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await save();
    await saveToFirebase();
  }

  Future<void> updateAccentColor(Color color) async {
    _accentColor = color;
    await save();
    await saveToFirebase();
  }

  Future<void> updateUseMaterialYou(bool use) async {
    _useMaterialYou = use;
    await save();
    await saveToFirebase();
  }

  Future<void> updateSortOrder(String order) async {
    _sortOrder = order;
    await save();
    await saveToFirebase();
  }

  Future<void> updateShowBirthday(bool show) async {
    _showBirthday = show;
    await save();
    await saveToFirebase();
  }
}
