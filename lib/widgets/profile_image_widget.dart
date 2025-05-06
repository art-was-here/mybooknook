import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileImageWidget extends StatefulWidget {
  final double size;
  final Color accentColor;

  const ProfileImageWidget({
    super.key,
    this.size = 40.0,
    required this.accentColor,
  });

  @override
  State<ProfileImageWidget> createState() => _ProfileImageWidgetState();
}

class _ProfileImageWidgetState extends State<ProfileImageWidget> {
  String? _cachedProfileImage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCachedProfileImage();
  }

  Future<void> _loadCachedProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedImage = prefs.getString('profile_image');

    if (cachedImage != null) {
      setState(() {
        _cachedProfileImage = cachedImage;
        _isLoading = false;
      });
    }

    _loadProfileImageFromFirebase();
  }

  Future<void> _loadProfileImageFromFirebase() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final imageUrl = userDoc.data()?['profileImage'] as String?;
        if (imageUrl != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('profile_image', imageUrl);

          if (mounted) {
            setState(() {
              _cachedProfileImage = imageUrl;
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      print('Error loading profile image: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: CircularProgressIndicator(
          color: widget.accentColor,
        ),
      );
    }

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.accentColor.withOpacity(0.1),
        image: _cachedProfileImage != null
            ? DecorationImage(
                image: NetworkImage(_cachedProfileImage!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: _cachedProfileImage == null
          ? Icon(
              Icons.person,
              size: widget.size * 0.6,
              color: widget.accentColor,
            )
          : null,
    );
  }
}
