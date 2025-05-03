import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'book_with_list.dart';

class ListManager {
  final BuildContext context;
  final Map<String, bool> _expandedLists = {};
  final Map<String, AnimationController> _animationControllers = {};
  final Map<String, Animation<double>> _listAnimations = {};

  ListManager(this.context);

  Map<String, bool> get expandedLists => _expandedLists;
  Map<String, AnimationController> get animationControllers =>
      _animationControllers;
  Map<String, Animation<double>> get listAnimations => _listAnimations;

  Future<void> loadExpandedStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final expandedStates = prefs.getString('expandedLists');
      if (expandedStates != null) {
        final Map<String, dynamic> states = json.decode(expandedStates);
        states.forEach((key, value) {
          _expandedLists[key] = value as bool;
        });
      }
    } catch (e) {
      print('Error loading expanded states: $e');
    }
  }

  Future<void> saveExpandedStates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('expandedLists', json.encode(_expandedLists));
    } catch (e) {
      print('Error saving expanded states: $e');
    }
  }

  void toggleListExpanded(String listName, TickerProviderStateMixin vsync) {
    final isExpanded = _expandedLists[listName] ?? true;
    _expandedLists[listName] = !isExpanded;

    if (!_animationControllers.containsKey(listName)) {
      _animationControllers[listName] = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 300),
      );
      _listAnimations[listName] = CurvedAnimation(
        parent: _animationControllers[listName]!,
        curve: Curves.easeInOut,
      );

      if (isExpanded) {
        _animationControllers[listName]!.value = 1.0;
      }
    }

    if (isExpanded) {
      _animationControllers[listName]!.reverse();
    } else {
      _animationControllers[listName]!.forward();
    }

    saveExpandedStates();
  }

  Animation<double> getAnimationForList(
      String listName, TickerProviderStateMixin vsync) {
    if (!_animationControllers.containsKey(listName)) {
      _animationControllers[listName] = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 300),
      );
      _listAnimations[listName] = CurvedAnimation(
        parent: _animationControllers[listName]!,
        curve: Curves.easeInOut,
      );

      if (_expandedLists[listName] ?? true) {
        _animationControllers[listName]!.value = 1.0;
      }
    }

    return _listAnimations[listName]!;
  }

  void dispose() {
    for (var controller in _animationControllers.values) {
      controller.dispose();
    }
  }
}
