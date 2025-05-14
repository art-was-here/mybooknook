import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'dart:async';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  late AndroidNotificationChannel _channel;
  StreamSubscription? _messagesSubscription;

  NotificationService._internal();

  Future<void> initialize() async {
    // Initialize local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationTap(response);
      },
    );

    // Create Android notification channel
    _channel = const AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
    );

    // Register the channel with the system
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Request notification permission for FCM
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get the token and save it
    String? token = await _firebaseMessaging.getToken();
    if (token != null) {
      await _saveTokenToFirestore(token);
    }

    // Listen for token refresh
    _firebaseMessaging.onTokenRefresh.listen(_saveTokenToFirestore);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Listen to the messages collection for this user
    await setupMessageListener();
  }

  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _firestore.collection('users').doc(user.uid).update({
          'fcmToken': token,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
        print('FCM token saved: $token');
      }
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    print('Received foreground message: ${message.messageId}');

    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    // If the message contains a notification and we're on Android,
    // we show a local notification
    if (notification != null && android != null) {
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            icon: android.smallIcon ?? '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: json.encode(message.data),
      );
    }
  }

  void _handleNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = json.decode(response.payload!);

        // Here you can handle navigation based on the notification type
        print('Notification tapped with data: $data');

        // Example: navigating based on notification type
        // if (data['type'] == 'message') {
        //   // Navigate to messages screen
        // }
      } catch (e) {
        print('Error handling notification tap: $e');
      }
    }
  }

  // Listen for new messages in Firestore and show notifications
  Future<void> setupMessageListener() async {
    // Cancel existing subscription if any
    await _messagesSubscription?.cancel();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Listen for messages added to the user's messages collection
    _messagesSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('messages')
        .where('isRead', isEqualTo: false)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        // Only process newly added documents
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;

          // Show local notification for the new message
          _showLocalNotification(
            id: change.doc.id.hashCode,
            title: data['title'] ?? 'New Message',
            body: data['body'] ?? 'You have a new message',
            payload: {'messageId': change.doc.id, 'type': 'message'},
          );
        }
      }
    });
  }

  void _showLocalNotification({
    required int id,
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) {
    _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload != null ? json.encode(payload) : null,
    );
  }

  // Send a test notification with a delay
  Future<void> sendTestNotification({int delaySeconds = 5}) async {
    // Create a unique ID based on timestamp
    final id = DateTime.now().millisecondsSinceEpoch.remainder(100000);

    // Show message that notification will arrive in X seconds
    print('Test notification will arrive in $delaySeconds seconds');

    // Wait for the specified delay
    await Future.delayed(Duration(seconds: delaySeconds));

    // Show the test notification
    _showLocalNotification(
      id: id,
      title: 'Test Notification',
      body:
          'This is a test notification from MyBookNook sent after $delaySeconds seconds',
      payload: {
        'type': 'test_notification',
        'timestamp': DateTime.now().toIso8601String()
      },
    );

    print('Test notification sent with ID: $id');
    return;
  }

  // Send a message to another user (this creates a document in Firestore)
  Future<void> sendMessageToUser({
    required String recipientUserId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Get the recipient's document to check if they exist
      final recipientDoc =
          await _firestore.collection('users').doc(recipientUserId).get();

      if (!recipientDoc.exists) {
        throw Exception('Recipient user not found');
      }

      // Add a message to the recipient's messages collection
      await _firestore
          .collection('users')
          .doc(recipientUserId)
          .collection('messages')
          .add({
        'title': title,
        'body': body,
        'senderId': user.uid,
        'senderName': user.displayName ?? 'Unknown User',
        'senderEmail': user.email,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'data': data ?? {},
      });

      print('Message sent to user $recipientUserId');
    } catch (e) {
      print('Error sending message: $e');
      rethrow;
    }
  }

  // Mark a message as read
  Future<void> markMessageAsRead(String messageId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('messages')
          .doc(messageId)
          .update({'isRead': true});
    } catch (e) {
      print('Error marking message as read: $e');
    }
  }

  // Clean up resources
  Future<void> dispose() async {
    await _messagesSubscription?.cancel();
  }
}
