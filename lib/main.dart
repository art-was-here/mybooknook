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
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasData) {
                  return StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(snapshot.data!.uid)
                        .snapshots(),
                    builder: (context, userSnapshot) {
                      if (userSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                        return const UsernameSetupScreen();
                      }
                      return HomeScreen(
                        onThemeChanged: _onThemeChanged,
                        accentColor: _accentColor,
                        onAccentColorChanged: _onAccentColorChanged,
                      );
                    },
                  );
                }
                return const AuthScreen();
              },
            ),
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

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
            ElevatedButton(
              onPressed: () async {
                try {
                  await FirebaseAuth.instance
                      .signInWithProvider(GoogleAuthProvider());
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error signing in: $e')),
                  );
                }
              },
              child: const Text('Sign in with Google'),
            ),
          ],
        ),
      ),
    );
  }
}
