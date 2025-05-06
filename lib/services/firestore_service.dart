import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  static bool _isInitialized = false;

  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await FirebaseFirestore.instance.enablePersistence();
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      _isInitialized = true;
    } catch (e) {
      print('Error enabling Firestore persistence: $e');
    }
  }

  static Future<void> clearPersistence() async {
    try {
      await FirebaseFirestore.instance.clearPersistence();
    } catch (e) {
      print('Error clearing Firestore persistence: $e');
    }
  }

  static Future<void> terminate() async {
    try {
      await FirebaseFirestore.instance.terminate();
      _isInitialized = false;
    } catch (e) {
      print('Error terminating Firestore: $e');
    }
  }
}
