import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/username_setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = Colors.teal; // Default accent color

  @override
  void initState() {
    super.initState();
    _loadAccentColor();
  }

  Future<void> _loadAccentColor() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        final savedColor = prefs.getInt('accentColor');
        _accentColor = savedColor != null ? Color(savedColor) : Colors.teal;
      });
    }
  }

  void _onThemeChanged(ThemeMode themeMode) {
    if (mounted) {
      setState(() {
        _themeMode = themeMode;
      });
    }
  }

  void _onAccentColorChanged(Color color) async {
    if (mounted) {
      setState(() {
        _accentColor = color;
      });
      // Save the accent color
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('accentColor', color.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyBookNook',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accentColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _accentColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: _themeMode,
      initialRoute: '/',
      routes: {
        '/': (context) => StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Scaffold(
                    body: Center(
                      child: Text('Error: ${snapshot.error}'),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const AuthScreen();
                }

                // User is authenticated, check if they have a document and setup is complete
                return FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(snapshot.data!.uid)
                      .get(),
                  builder: (context, userSnapshot) {
                    if (userSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Scaffold(
                        body: Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    if (userSnapshot.hasError) {
                      return Scaffold(
                        body: Center(
                          child: Text('Error: ${userSnapshot.error}'),
                        ),
                      );
                    }

                    // If user document doesn't exist or setup is not complete
                    if (!userSnapshot.hasData ||
                        !userSnapshot.data!.exists ||
                        (userSnapshot.data!.data()
                                as Map<String, dynamic>)['setupComplete'] !=
                            true) {
                      // Instead of signing out, navigate to username setup
                      return const UsernameSetupScreen();
                    }

                    // User is authenticated and has completed setup, show home screen
                    return HomeScreen(
                      onThemeChanged: _onThemeChanged,
                      accentColor: _accentColor,
                      onAccentColorChanged: _onAccentColorChanged,
                    );
                  },
                );
              },
            ),
        '/login': (context) => const AuthScreen(),
        '/username-setup': (context) => const UsernameSetupScreen(),
        '/settings': (context) => SettingsScreen(
              onThemeChanged: _onThemeChanged,
              onAccentColorChanged: _onAccentColorChanged,
              onSortOrderChanged: (value) {
                // TODO: Implement sort order change
              },
              accentColor: _accentColor,
            ),
        '/profile': (context) => const ProfileScreen(),
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  DateTime? _lastBackPress;

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // First, sign out to clear any existing state
      await FirebaseAuth.instance.signOut();

      // Then attempt to sign in
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      googleProvider.addScope('https://www.googleapis.com/auth/books');

      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithProvider(googleProvider);

      if (userCredential.user == null) {
        throw Exception('Failed to get user data after sign in');
      }

      // Wait for the auth state to be fully updated
      await Future.delayed(const Duration(milliseconds: 500));

      // Check if this is a new user
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (!userDoc.exists) {
        // Create a new user document with setupComplete flag
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'email': userCredential.user!.email,
          'displayName': userCredential.user!.displayName,
          'createdAt': FieldValue.serverTimestamp(),
          'setupComplete': false,
        });
      }

      // Let the main app handle the navigation based on setup state
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/');
      }
    } catch (e) {
      print('Sign in error: $e');
      setState(() {
        _errorMessage = 'Failed to sign in: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
        return true;
      },
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Welcome to myBookNook!',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Please sign-in to get started',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ElevatedButton(
                  onPressed: _isLoading ? null : _signInWithGoogle,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Sign in with Google'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
