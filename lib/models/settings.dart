import 'package:shared_preferences/shared_preferences.dart';

class Settings {
  static const String _fontSizeKey = 'font_size';
  static const String _listDensityKey = 'list_density';
  static const String _lastExportDateKey = 'last_export_date';
  static const String _lastImportDateKey = 'last_import_date';
  static const String _totalBooksKey = 'total_books';
  static const String _readBooksKey = 'read_books';

  double _fontSize = 1.0;
  String _listDensity = 'comfortable';
  DateTime? _lastExportDate;
  DateTime? _lastImportDate;
  int _totalBooks = 0;
  int _readBooks = 0;

  // Getters
  double get fontSize => _fontSize;
  String get listDensity => _listDensity;
  DateTime? get lastExportDate => _lastExportDate;
  DateTime? get lastImportDate => _lastImportDate;
  int get totalBooks => _totalBooks;
  int get readBooks => _readBooks;
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
  }

  // Update methods
  Future<void> updateFontSize(double size) async {
    _fontSize = size;
    await save();
  }

  Future<void> updateListDensity(String density) async {
    _listDensity = density;
    await save();
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
}
