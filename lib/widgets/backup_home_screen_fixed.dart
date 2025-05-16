import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_expandable_fab/flutter_expandable_fab.dart';
import 'dart:async';
import 'dart:convert';

// This is a minimal version just to test the menu animation
class HomeScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final Color accentColor;
  final Function(Color) onAccentColorChanged;

  const HomeScreen({
    super.key,
    required this.onThemeChanged,
    required this.accentColor,
    required this.onAccentColorChanged,
  });

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isMenuOpen = false;
  double _menuWidth = 280.0;
  double _dragStartX = 0.0;
  double _currentDragX = 0.0;
  String _selectedListName = 'Library';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Side Menu
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _menuWidth,
            child: Container(
              color: Color.lerp(
                Theme.of(context).scaffoldBackgroundColor,
                Colors.white,
                0.03,
              ),
              child: ListView(
                padding: const EdgeInsets.only(top: 16.0),
                children: [
                  const SizedBox(height: 40), // Add space for AppBar
                  ListTile(
                    leading: Icon(Icons.home,
                        color: Theme.of(context).colorScheme.primary),
                    title: const Text('Library'),
                    onTap: () {
                      setState(() {
                        _isMenuOpen = false;
                        _currentDragX = 0.0;
                      });
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: Icon(Icons.person,
                        color: Theme.of(context).colorScheme.primary),
                    title: const Text('Profile'),
                    onTap: () {
                      setState(() {
                        _isMenuOpen = false;
                        _currentDragX = 0.0;
                      });
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.search,
                        color: Theme.of(context).colorScheme.primary),
                    title: const Text('Search'),
                    onTap: () {
                      setState(() {
                        _isMenuOpen = false;
                        _currentDragX = 0.0;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // Main Content with Slide Effect
          GestureDetector(
            onHorizontalDragStart: (details) {
              _dragStartX = details.globalPosition.dx;
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                _currentDragX = (_isMenuOpen ? _menuWidth : 0.0) +
                    (details.globalPosition.dx - _dragStartX);
                _currentDragX = _currentDragX.clamp(0.0, _menuWidth);
              });
            },
            onHorizontalDragEnd: (details) {
              setState(() {
                if (_currentDragX > _menuWidth / 2) {
                  _isMenuOpen = true;
                  _currentDragX = _menuWidth;
                } else {
                  _isMenuOpen = false;
                  _currentDragX = 0.0;
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              transform: Matrix4.translationValues(_currentDragX, 0.0, 0.0),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16.0),
                  bottomLeft: Radius.circular(16.0),
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.black.withOpacity(_currentDragX > 0 ? 0.1 : 0.0),
                    blurRadius: 8.0,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16.0),
                  bottomLeft: Radius.circular(16.0),
                ),
                child: Column(
                  children: [
                    AppBar(
                      title: Text(_selectedListName),
                      leading: IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () {
                          setState(() {
                            _isMenuOpen = !_isMenuOpen;
                            _currentDragX = _isMenuOpen ? _menuWidth : 0.0;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text('Content goes here'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
