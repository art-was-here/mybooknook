import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'dart:async';
import 'dart:convert';
import 'widgets/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/username_setup_screen.dart';
import 'models/book.dart';
import 'widgets/scan_book_details_card.dart';
import 'services/book_service.dart';
import 'screens/search_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/chat_room_screen.dart';
import 'services/notification_service.dart';

// Handle background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('Handling a background message: ${message.messageId}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize Firebase Cloud Messaging
  final messaging = FirebaseMessaging.instance;

  // Request permission for notifications
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  print('User granted permission: ${settings.authorizationStatus}');

  // Set up background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('Got a message whilst in the foreground!');
    print('Message data: ${message.data}');

    if (message.notification != null) {
      print('Message also contained a notification: ${message.notification}');
    }
  });

  // Handle notification taps when app is in background
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print('Message clicked!');
    print('Message data: ${message.data}');
  });

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
  late AppLinks _appLinks;
  StreamSubscription? _linkSubscription;
  Book? _sharedBook;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  String? _fcmToken;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _loadAccentColor();
    _initDeepLinkListener();
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    try {
      await _notificationService.initialize();
    } catch (e) {
      print('Error initializing notifications: $e');
    }
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
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

  Future<void> _initDeepLinkListener() async {
    try {
      print('Initializing deep link listener...');
      _appLinks = AppLinks();

      // Handle initial link if the app was launched from a link
      print('Checking for initial link...');
      final initialLink = await _appLinks.getInitialAppLink();
      if (initialLink != null) {
        print('Got initial link: ${initialLink.toString()}');
        _handleDeepLink(initialLink);
      } else {
        print('No initial link found');
      }

      // Handle links when app is already running
      print('Setting up link stream listener...');
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (uri) {
          print('Received link while app is running: ${uri.toString()}');
          _handleDeepLink(uri);
        },
        onError: (err) {
          print('Error in link stream: $err');
        },
        cancelOnError: false,
      );
      print('Deep link listener initialized successfully');
    } catch (e) {
      print('Error initializing deep link listener: $e');
    }
  }

  void _handleDeepLink(Uri uri) async {
    print('\n=== Deep Link Handling Started ===');
    print('URI received: ${uri.toString()}');
    print('URI path: ${uri.path}');
    print('URI query parameters: ${uri.queryParameters}');

    // Check if this is a book deep link by looking for the 'book' host
    if (uri.host == 'book') {
      try {
        final isbn = uri.queryParameters['isbn'];
        print('ISBN extracted: $isbn');

        if (isbn != null) {
          print('Waiting for navigator to be ready...');
          await Future.delayed(const Duration(milliseconds: 500));

          if (!mounted) {
            print('Widget not mounted, aborting');
            return;
          }

          print('Getting navigator context...');
          final context = _navigatorKey.currentContext;
          if (context == null) {
            print('No valid navigator context found');
            return;
          }
          print('Got valid navigator context');

          print('Creating BookService...');
          final bookService = BookService(context);

          print('Fetching book details for ISBN: $isbn');
          final book = await bookService.fetchBookDetails(isbn);

          if (book != null) {
            print('Book found: ${book.title}');
            print('Getting user lists...');

            // Get the current user's lists
            final user = FirebaseAuth.instance.currentUser;
            Map<String, String> lists = {};

            if (user != null) {
              print('User logged in: ${user.uid}');
              final listsSnapshot = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('lists')
                  .get();

              print('Found ${listsSnapshot.docs.length} lists');
              for (var doc in listsSnapshot.docs) {
                lists[doc.id] = doc.data()['name'] as String;
              }
            } else {
              print('No user logged in');
            }

            if (!mounted) {
              print('Widget not mounted after fetching data, aborting');
              return;
            }

            print('Showing ScanBookDetailsCard...');
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (BuildContext context) {
                print('Building ScanBookDetailsCard');
                return ScanBookDetailsCard(
                  book: book,
                  bookService: bookService,
                  lists: lists,
                  onClose: () {
                    print('ScanBookDetailsCard closed');
                    Navigator.pop(context);
                  },
                );
              },
            );
            print('Modal bottom sheet shown');
          } else {
            print('Book not found for ISBN: $isbn');
            if (mounted && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Book not found')),
              );
            }
          }
        } else {
          print('No ISBN found in URL parameters');
        }
      } catch (e, stackTrace) {
        print('Error handling deep link: $e');
        print('Stack trace: $stackTrace');
      }
    } else {
      print('Not a book deep link: ${uri.host}');
    }
    print('=== Deep Link Handling Completed ===\n');
  }

  Future<void> _setupFCM() async {
    try {
      // Get FCM token
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        setState(() {
          _fcmToken = token;
        });

        // Save FCM token to Firestore for the current user
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'fcmToken': token});
        }
      }

      // Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'fcmToken': token});
        }
      });
    } catch (e) {
      print('Error setting up FCM: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
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
        '/search': (context) => const SearchScreen(),
        '/notifications': (context) => const NotificationsScreen(),
        '/messages': (context) => const MessagesScreen(),
        // ChatRoomScreen requires parameters, so we navigate to it directly from MessagesScreen
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
