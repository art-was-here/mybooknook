import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:async';

class SideMenu extends StatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;

  const SideMenu({
    Key? key,
    required this.child,
    required this.navigatorKey,
  }) : super(key: key);

  @override
  State<SideMenu> createState() => SideMenuState();
}

class SideMenuState extends State<SideMenu> {
  bool _isMenuOpen = false;
  double _menuWidth = 280.0;
  double _dragStartX = 0.0;
  double _currentDragX = 0.0;
  String? _cachedProfileImage;

  void closeMenu() {
    if (_isMenuOpen) {
      setState(() {
        _isMenuOpen = false;
        _currentDragX = 0.0;
      });
    }
  }

  Future<void> _navigateToRoute(String routeName) async {
    // Close the menu first
    setState(() {
      _isMenuOpen = false;
      _currentDragX = 0.0;
    });

    // Wait for the animation to complete
    await Future.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    // Navigate to the route
    final context = widget.navigatorKey.currentContext;
    if (context != null) {
      Navigator.pushNamed(context, routeName);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if the child is a Scaffold with a floating action button
    Widget childWidget = widget.child;
    if (widget.child is Scaffold) {
      final Scaffold scaffold = widget.child as Scaffold;
      if (scaffold.floatingActionButton != null) {
        // Create a new scaffold that preserves the FAB
        childWidget = Scaffold(
          body: scaffold.body,
          appBar: scaffold.appBar,
          floatingActionButton: scaffold.floatingActionButton,
          floatingActionButtonLocation: scaffold.floatingActionButtonLocation,
          floatingActionButtonAnimator: scaffold.floatingActionButtonAnimator,
        );
      }
    }

    return Stack(
      children: [
        // Main content with gesture detector
        Positioned.fill(
          child: GestureDetector(
            onHorizontalDragStart: (details) {
              // Only allow drag if we're at the root route
              if (widget.navigatorKey.currentContext != null) {
                final canPop =
                    Navigator.canPop(widget.navigatorKey.currentContext!);
                if (!canPop) {
                  _dragStartX = details.globalPosition.dx;
                }
              }
            },
            onHorizontalDragUpdate: (details) {
              if (_dragStartX < 20 && !_isMenuOpen) {
                setState(() {
                  final delta = details.globalPosition.dx - _dragStartX;
                  if (delta > 0) {
                    _currentDragX = delta.clamp(0.0, _menuWidth);
                  }
                });
              }
            },
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              setState(() {
                if (velocity > 300 || _currentDragX > _menuWidth / 3) {
                  _isMenuOpen = true;
                } else {
                  _isMenuOpen = false;
                }
                _currentDragX = _isMenuOpen ? _menuWidth : 0.0;
              });
            },
            child: childWidget,
          ),
        ),

        // Semi-transparent overlay when menu is open
        if (_isMenuOpen)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: closeMenu,
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
          ),

        // Side Menu
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuad,
          left: _isMenuOpen ? 0 : -_menuWidth + _currentDragX,
          top: 0,
          bottom: 0,
          width: _menuWidth,
          child: Material(
            elevation: 10,
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: Color.lerp(
                  Theme.of(context).scaffoldBackgroundColor,
                  Colors.white,
                  0.03,
                ),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(17.6),
                  bottomRight: Radius.circular(17.6),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 8),
              child: Center(
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    // Profile Section
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16.0, vertical: 8.0),
                      child: Row(
                        children: [
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseAuth.instance.currentUser != null
                                ? FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(FirebaseAuth.instance.currentUser!.uid)
                                    .snapshots()
                                : Stream.empty(),
                            builder: (context, snapshot) {
                              String? profileImage;
                              if (snapshot.hasData && snapshot.data != null) {
                                final data = snapshot.data!.data()
                                    as Map<String, dynamic>?;
                                profileImage =
                                    data?['profileImageBase64'] as String?;
                              }

                              return CircleAvatar(
                                radius: 24,
                                backgroundImage: profileImage != null
                                    ? MemoryImage(base64Decode(profileImage))
                                    : null,
                                child: profileImage == null
                                    ? const Icon(Icons.person)
                                    : null,
                              );
                            },
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseAuth.instance.currentUser != null
                                  ? FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(FirebaseAuth
                                          .instance.currentUser!.uid)
                                      .snapshots()
                                  : Stream.empty(),
                              builder: (context, snapshot) {
                                if (snapshot.hasData && snapshot.data != null) {
                                  final data = snapshot.data!.data()
                                      as Map<String, dynamic>?;
                                  final username =
                                      data?['username'] as String? ?? 'user';
                                  return Text(
                                    '@$username',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  );
                                }
                                return const Text('@user');
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5.0),
                      child: const Divider(),
                    ),
                    ListTile(
                      leading: Icon(Icons.home,
                          color: Theme.of(context).colorScheme.primary),
                      title: const Text('Library'),
                      onTap: () => _navigateToRoute('/'),
                    ),
                    ListTile(
                      leading: Icon(Icons.person,
                          color: Theme.of(context).colorScheme.primary),
                      title: const Text('Profile'),
                      onTap: () => _navigateToRoute('/profile'),
                    ),
                    ListTile(
                      leading: Icon(Icons.search,
                          color: Theme.of(context).colorScheme.primary),
                      title: const Text('Search'),
                      onTap: () => _navigateToRoute('/search'),
                    ),
                    ListTile(
                      leading: Icon(Icons.notifications,
                          color: Theme.of(context).colorScheme.primary),
                      title: const Text('Notifications'),
                      trailing: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseAuth.instance.currentUser != null
                            ? FirebaseFirestore.instance
                                .collection('users')
                                .doc(FirebaseAuth.instance.currentUser!.uid)
                                .collection('notifications')
                                .where('isRead', isEqualTo: false)
                                .snapshots()
                            : Stream.empty(),
                        builder: (context, snapshot) {
                          final unreadCount = snapshot.data?.docs.length ?? 0;
                          if (unreadCount == 0) {
                            return const SizedBox.shrink();
                          }
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              unreadCount.toString(),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                      onTap: () => _navigateToRoute('/notifications'),
                    ),
                    ListTile(
                      leading: Icon(Icons.message,
                          color: Theme.of(context).colorScheme.primary),
                      title: const Text('Messages'),
                      onTap: () => _navigateToRoute('/messages'),
                    ),
                    ListTile(
                      leading: Icon(Icons.settings,
                          color: Theme.of(context).colorScheme.primary),
                      title: const Text('Settings'),
                      onTap: () => _navigateToRoute('/settings'),
                    ),
                    const Divider(),
                    ListTile(
                      leading: Icon(Icons.logout,
                          color: Theme.of(context).colorScheme.primary),
                      title: const Text('Logout'),
                      onTap: () {
                        closeMenu();
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Logout'),
                            content:
                                const Text('Are you sure you want to logout?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await FirebaseAuth.instance.signOut();
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    Navigator.pushReplacementNamed(
                                        context, '/login');
                                  }
                                },
                                child: const Text('Logout'),
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
          ),
        ),
      ],
    );
  }
}
