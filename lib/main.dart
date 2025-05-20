import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_links/app_links.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
import 'services/update_service.dart';
import 'widgets/side_menu.dart';

// A key to access the same instance of MyApp when rebuilding
final GlobalKey<_MyAppState> myAppKey = GlobalKey<_MyAppState>();

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

  runApp(MyApp(key: myAppKey));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  // Static method to restart the app
  static void restartApp(BuildContext context) {
    final _MyAppState? state = myAppKey.currentState;
    if (state != null) {
      state._restartApp();
    }
  }

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Color _accentColor = Colors.teal; // Default accent color
  bool _useMaterialYou = false; // Default Material You setting
  late AppLinks _appLinks;
  StreamSubscription? _linkSubscription;
  Book? _sharedBook;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  String? _fcmToken;
  final NotificationService _notificationService = NotificationService();
  final UpdateService _updateService = UpdateService(
    owner: 'art-was-here', // Replace with your GitHub username
    repo: 'mybooknook', // Replace with your repo name
  );
  // Add a key to force widget rebuilds
  Key _appKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initDeepLinkListener();
    _initializeNotifications();
    _setupFCM();

    // Check for updates after a short delay
    Future.delayed(const Duration(seconds: 3), () {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    try {
      final release = await _updateService.checkForUpdates();
      if (release != null && mounted) {
        // A new version is available
        final context = _navigatorKey.currentContext;
        if (context != null) {
          await _updateService.showUpdateDialog(context, release);
        }
      }
    } catch (e) {
      print('Error checking for updates: $e');
    }
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

  Future<void> _loadSettings() async {
    await _loadAccentColor();
    await _loadMaterialYouSetting();
    await _loadThemeMode();
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        final themeMode = prefs.getString('themeMode') ?? 'system';
        _themeMode = ThemeMode.values.firstWhere(
          (mode) => mode.toString() == 'ThemeMode.$themeMode',
          orElse: () => ThemeMode.system,
        );
      });
    }
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

  Future<void> _loadMaterialYouSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _useMaterialYou = prefs.getBool('use_material_you') ?? false;
        print('Material You setting loaded: $_useMaterialYou');
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

  void _onMaterialYouChanged(bool value) async {
    if (mounted) {
      // Save the Material You setting first
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('use_material_you', value);

      // Then update the state
      setState(() {
        _useMaterialYou = value;
      });

      // Add debug print statements
      print('Material You setting changed to: $value');

      // Force a complete app restart
      _restartApp();
    }
  }

  void _restartApp() {
    setState(() {
      // Change the key to force a complete rebuild
      _appKey = UniqueKey();
    });

    print('App restarted with new key: $_appKey');
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
    return KeyedSubtree(
      key: _appKey,
      child: DynamicColorBuilder(
        builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
          // Print debug information
          print('=== Material You Debug ===');
          print('Material You enabled: $_useMaterialYou');
          print(
              'Light dynamic color scheme available: ${lightDynamic != null}');
          print('Dark dynamic color scheme available: ${darkDynamic != null}');

          if (lightDynamic != null) {
            print('Light dynamic primary: ${lightDynamic.primary}');
            print('Light dynamic tertiary: ${lightDynamic.tertiary}');
          }

          // Create seed-generated schemes based on accent color
          final seedLightScheme = ColorScheme.fromSeed(
            seedColor: _accentColor,
            brightness: Brightness.light,
          );

          final seedDarkScheme = ColorScheme.fromSeed(
            seedColor: _accentColor,
            brightness: Brightness.dark,
          );

          // Decide which scheme to use based on Material You setting
          final ColorScheme effectiveLightScheme =
              _useMaterialYou && lightDynamic != null
                  ? lightDynamic
                  : seedLightScheme;

          final ColorScheme effectiveDarkScheme =
              _useMaterialYou && darkDynamic != null
                  ? darkDynamic
                  : seedDarkScheme;

          print(
              'Effective light scheme primary: ${effectiveLightScheme.primary}');
          print(
              'Effective light scheme tertiary: ${effectiveLightScheme.tertiary}');
          print(
              'Effective dark scheme primary: ${effectiveDarkScheme.primary}');
          print(
              'Effective dark scheme tertiary: ${effectiveDarkScheme.tertiary}');
          print('Using Material You: $_useMaterialYou');
          print('=== End Material You Debug ===');

          // Create slightly brighter surface colors for cards when Material You is enabled
          final Color lightCardColor = _useMaterialYou
              ? _brightenColor(effectiveLightScheme.surface, 0.03)
              : effectiveLightScheme.surface;

          final Color darkCardColor = _useMaterialYou
              ? _brightenColor(effectiveDarkScheme.surface, 0.03)
              : _brightenColor(effectiveDarkScheme.background, 0.03);

          // Get the appropriate FAB colors
          final Color lightFabColor = _useMaterialYou && lightDynamic != null
              ? lightDynamic.tertiary
              : effectiveLightScheme.primary;

          final Color darkFabColor = _useMaterialYou && darkDynamic != null
              ? darkDynamic.tertiary
              : effectiveDarkScheme.primary;

          print('=== FAB Color Debug ===');
          print('Material You enabled: $_useMaterialYou');
          print('Light dynamic available: ${lightDynamic != null}');
          print('Dark dynamic available: ${darkDynamic != null}');
          if (lightDynamic != null) {
            print('Light dynamic tertiary: ${lightDynamic.tertiary}');
            print('Light dynamic onTertiary: ${lightDynamic.onTertiary}');
          }
          print('Light FAB color: $lightFabColor');
          print('Dark FAB color: $darkFabColor');
          print('=== End FAB Color Debug ===');

          return MaterialApp(
            navigatorKey: _navigatorKey,
            title: 'MyBookNook',
            // Light theme with dynamic or seed colors
            theme: ThemeData(
              colorScheme: effectiveLightScheme,
              useMaterial3: true,
              // Make sure components explicitly use the color scheme
              brightness: Brightness.light,
              primaryColor: effectiveLightScheme.primary,
              scaffoldBackgroundColor: effectiveLightScheme.background,
              cardColor: lightCardColor,
              cardTheme: CardTheme(
                color: lightCardColor,
                elevation: 2,
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: effectiveLightScheme.surface,
                foregroundColor: effectiveLightScheme.onSurface,
              ),
              buttonTheme: ButtonThemeData(
                colorScheme: effectiveLightScheme,
                buttonColor: effectiveLightScheme.primary,
              ),
              textButtonTheme: TextButtonThemeData(
                style: ButtonStyle(
                  foregroundColor:
                      MaterialStateProperty.all(effectiveLightScheme.primary),
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: effectiveLightScheme.primary,
                  foregroundColor: effectiveLightScheme.onPrimary,
                ),
              ),
              floatingActionButtonTheme: FloatingActionButtonThemeData(
                backgroundColor: lightFabColor,
                foregroundColor: _useMaterialYou && lightDynamic != null
                    ? lightDynamic.onTertiary
                    : effectiveLightScheme.onPrimary,
              ),
              snackBarTheme: SnackBarThemeData(
                backgroundColor: _useMaterialYou && lightDynamic != null
                    ? lightDynamic.tertiary
                    : lightFabColor,
                contentTextStyle: TextStyle(
                  color: _useMaterialYou && lightDynamic != null
                      ? lightDynamic.onTertiary
                      : effectiveLightScheme.onPrimary,
                ),
              ),
              switchTheme: SwitchThemeData(
                thumbColor: MaterialStateProperty.resolveWith((states) {
                  if (_useMaterialYou && lightDynamic != null) {
                    return states.contains(MaterialState.selected)
                        ? lightDynamic.tertiary
                        : lightDynamic.outline;
                  }
                  return states.contains(MaterialState.selected)
                      ? effectiveLightScheme.primary
                      : effectiveLightScheme.outline;
                }),
                trackColor: MaterialStateProperty.resolveWith((states) {
                  if (_useMaterialYou && lightDynamic != null) {
                    return states.contains(MaterialState.selected)
                        ? lightDynamic.tertiaryContainer
                        : lightDynamic.surfaceVariant;
                  }
                  return states.contains(MaterialState.selected)
                      ? effectiveLightScheme.primaryContainer
                      : effectiveLightScheme.surfaceVariant;
                }),
              ),
            ),
            // Dark theme with dynamic or seed colors
            darkTheme: ThemeData(
              colorScheme: effectiveDarkScheme,
              useMaterial3: true,
              // Make sure components explicitly use the color scheme
              brightness: Brightness.dark,
              primaryColor: effectiveDarkScheme.primary,
              scaffoldBackgroundColor: effectiveDarkScheme.background,
              cardColor: darkCardColor,
              cardTheme: CardTheme(
                color: darkCardColor,
                elevation: 2,
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: effectiveDarkScheme.surface,
                foregroundColor: effectiveDarkScheme.onSurface,
              ),
              buttonTheme: ButtonThemeData(
                colorScheme: effectiveDarkScheme,
                buttonColor: effectiveDarkScheme.primary,
              ),
              textButtonTheme: TextButtonThemeData(
                style: ButtonStyle(
                  foregroundColor:
                      MaterialStateProperty.all(effectiveDarkScheme.primary),
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: effectiveDarkScheme.primary,
                  foregroundColor: effectiveDarkScheme.onPrimary,
                ),
              ),
              floatingActionButtonTheme: FloatingActionButtonThemeData(
                backgroundColor: darkFabColor,
                foregroundColor: _useMaterialYou && darkDynamic != null
                    ? darkDynamic.onTertiary
                    : effectiveDarkScheme.onPrimary,
              ),
              snackBarTheme: SnackBarThemeData(
                backgroundColor: _useMaterialYou && darkDynamic != null
                    ? darkDynamic.tertiary
                    : darkFabColor,
                contentTextStyle: TextStyle(
                  color: _useMaterialYou && darkDynamic != null
                      ? darkDynamic.onTertiary
                      : effectiveDarkScheme.onPrimary,
                ),
              ),
              switchTheme: SwitchThemeData(
                thumbColor: MaterialStateProperty.resolveWith((states) {
                  if (_useMaterialYou && darkDynamic != null) {
                    return states.contains(MaterialState.selected)
                        ? darkDynamic.tertiary
                        : darkDynamic.outline;
                  }
                  return states.contains(MaterialState.selected)
                      ? effectiveDarkScheme.primary
                      : effectiveDarkScheme.outline;
                }),
                trackColor: MaterialStateProperty.resolveWith((states) {
                  if (_useMaterialYou && darkDynamic != null) {
                    return states.contains(MaterialState.selected)
                        ? darkDynamic.tertiaryContainer
                        : darkDynamic.surfaceVariant;
                  }
                  return states.contains(MaterialState.selected)
                      ? effectiveDarkScheme.primaryContainer
                      : effectiveDarkScheme.surfaceVariant;
                }),
              ),
            ),
            themeMode: _themeMode,
            builder: (context, child) {
              // Wrap the app with our side menu
              return SideMenu(
                navigatorKey: _navigatorKey,
                child: child!,
              );
            },
            initialRoute: '/',
            onGenerateRoute: (settings) {
              final routes = {
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
                              (userSnapshot.data!.data() as Map<String,
                                      dynamic>)['setupComplete'] !=
                                  true) {
                            // Instead of signing out, navigate to username setup
                            return const UsernameSetupScreen();
                          }

                          // User is authenticated and has completed setup, show home screen
                          return HomeScreen(
                            onThemeChanged: _onThemeChanged,
                            accentColor: _accentColor,
                            onAccentColorChanged: _onAccentColorChanged,
                            onMaterialYouChanged: _onMaterialYouChanged,
                          );
                        },
                      );
                    }),
                '/login': (context) => const AuthScreen(),
                '/username-setup': (context) => const UsernameSetupScreen(),
                '/settings': (context) => SettingsScreen(
                      onThemeChanged: _onThemeChanged,
                      onAccentColorChanged: _onAccentColorChanged,
                      onMaterialYouChanged: _onMaterialYouChanged,
                      onSortOrderChanged: (value) {
                        // TODO: Implement sort order change
                      },
                      accentColor: _accentColor,
                    ),
                '/profile': (context) => const ProfileScreen(),
                '/search': (context) => const SearchScreen(),
                '/notifications': (context) => const NotificationsScreen(),
                '/messages': (context) => const MessagesScreen(),
              };

              return PageRouteBuilder(
                settings: settings,
                pageBuilder: (context, animation, secondaryAnimation) {
                  // Get the route name from settings
                  final routeName = settings.name ?? '/';
                  // Get the route builder from the routes map
                  final routeBuilder = routes[routeName];
                  if (routeBuilder == null) {
                    return const Scaffold(
                      body: Center(
                        child: Text('Route not found'),
                      ),
                    );
                  }
                  return routeBuilder(context);
                },
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                  const begin = Offset(1.0, 0.0);
                  const end = Offset.zero;
                  const curve = Curves.easeInOut;
                  var tween = Tween(begin: begin, end: end)
                      .chain(CurveTween(curve: curve));
                  var offsetAnimation = animation.drive(tween);
                  return SlideTransition(
                    position: offsetAnimation,
                    child: child,
                  );
                },
                transitionDuration: const Duration(milliseconds: 300),
              );
            },
          );
        },
      ),
    );
  }

  // Helper method to brighten a color by a percentage
  Color _brightenColor(Color color, double amount) {
    assert(amount >= 0 && amount <= 1);

    // Convert to HSL
    final hsl = HSLColor.fromColor(color);

    // Increase lightness by the specified amount
    final newLightness = (hsl.lightness + amount).clamp(0.0, 1.0);

    // Create new color with increased lightness
    return hsl.withLightness(newLightness).toColor();
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
