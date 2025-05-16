// lib/services/notification_service.dart
// Complete implementation with all issues fixed

import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // Channel IDs for Android
  static const String _channelId = 'high_importance_channel';
  static const String _channelIdCheckRequests = 'check_requests_channel';

  // Stream controller for handling notification taps
  final StreamController<Map<String, dynamic>> _notificationStreamController =
  StreamController<Map<String, dynamic>>.broadcast();

  // Expose stream for listening to notification taps
  Stream<Map<String, dynamic>> get notificationStream => _notificationStreamController.stream;

  NotificationService() {
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    // Request permission for iOS and Android >= 13
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true, // For important notifications
      provisional: false,
    );

    debugPrint('User notification permission status: ${settings.authorizationStatus}');

    // Create Android notification channels
    await _createNotificationChannels();

    // Get the token
    String? token = await _firebaseMessaging.getToken();
    await _saveToken(token);

    // Listen for token refreshes
    _firebaseMessaging.onTokenRefresh.listen(_saveToken);

    // Initialize local notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      defaultPresentAlert: true,   // Show alert even when app is in foreground
      defaultPresentBadge: true,   // Update badge even when app is in foreground
      defaultPresentSound: true,   // Play sound even when app is in foreground
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
    );

    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle when a notification is tapped and the app is in the background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

    // Enable foreground notifications on iOS
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,   // Required to show alert
      badge: true,   // Required to update badge
      sound: true,   // Required to play sound
    );

    // Handle when the app is terminated and opened from a notification
    await _checkForInitialMessage();

    debugPrint("Notification service initialized successfully");
  }

  // Create notification channels for Android
  Future<void> _createNotificationChannels() async {
    // Main high importance channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    // Check requests specific channel
    const AndroidNotificationChannel checkRequestsChannel = AndroidNotificationChannel(
      _channelIdCheckRequests,
      'Check Requests',
      description: 'Notifications about check-in and check-out approval requests.',
      importance: Importance.high,
      enableVibration: true,
      playSound: true,
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(checkRequestsChannel);

    debugPrint("Android notification channels created");
  }

  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    final Map<String, dynamic> payload = response.payload != null && response.payload!.isNotEmpty
        ? jsonDecode(response.payload!) as Map<String, dynamic>
        : {};

    debugPrint("Notification tapped with payload: $payload");

    // Add flag to indicate this is from a notification tap
    payload['fromNotificationTap'] = 'true';

    _notificationStreamController.add(payload);
  }

  Future<void> _checkForInitialMessage() async {
    // Check if app was opened from a notification when it was terminated
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      debugPrint("App opened from terminated state with notification: ${initialMessage.messageId}");

      // Add a flag to indicate this is from initial notification
      final Map<String, dynamic> data = Map<String, dynamic>.from(initialMessage.data);
      data['fromNotificationTap'] = 'true';

      _handleBackgroundMessage(initialMessage);
    }
  }

  Future<void> _saveToken(String? token) async {
    if (token == null) return;

    debugPrint('FCM Token: $token');

    // Save the token to shared preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('Received foreground message: ${message.messageId}');
    debugPrint('Message data: ${message.data}');

    if (message.notification != null) {
      debugPrint('Message also contained a notification: ${message.notification?.title}');

      // Determine the notification channel based on the request type
      String channelId = _channelId; // Default channel
      String channelName = 'High Importance Notifications';
      String channelDescription = 'This channel is used for important notifications.';

      // Check if it's a check-in/check-out related notification
      if (message.data.containsKey('type')) {
        final notificationType = message.data['type'];

        if (notificationType == 'check_out_request_update' ||
            notificationType == 'new_check_out_request') {
          // Use specific channel for check-in/check-out requests
          channelId = _channelIdCheckRequests;
          channelName = 'Check Requests';
          channelDescription = 'Notifications about check-in and check-out approval requests';
        }
      }

      await _showLocalNotification(message, channelId, channelName, channelDescription);
    }
  }

  void _handleBackgroundMessage(RemoteMessage message) {
    debugPrint('Handling a background message: ${message.messageId}');

    // Add to stream controller to navigate if needed
    if (message.data.isNotEmpty) {
      // Add a flag to indicate this is from a background message
      final Map<String, dynamic> data = Map<String, dynamic>.from(message.data);
      data['fromNotificationTap'] = 'true';

      _notificationStreamController.add(data);
    }
  }

  Future<void> _showLocalNotification(
      RemoteMessage message,
      String channelId,
      String channelName,
      String channelDescription
      ) async {
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null) {
      // Create platform-specific notification details
      final AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        showWhen: true,
        icon: android?.smallIcon ?? 'mipmap/ic_launcher',
        // Remove the problematic largeIcon property
        color: Colors.blue, // Use your app's accent color
        enableLights: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(notification.body ?? ''),
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
      DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive, // Higher priority for iOS
      );

      final NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      // Show the notification
      await _flutterLocalNotificationsPlugin.show(
        // Use a unique ID based on timestamp
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        notification.title,
        notification.body,
        platformChannelSpecifics,
        payload: jsonEncode(message.data),
      );

      debugPrint("Local notification displayed: ${notification.title}");
    }
  }

  // Subscribe to topics for targeted notifications
  Future<void> subscribeToManagerTopic(String managerId) async {
    await _firebaseMessaging.subscribeToTopic('manager_$managerId');
    debugPrint('Subscribed to manager_$managerId topic');
  }

  Future<void> unsubscribeFromManagerTopic(String managerId) async {
    await _firebaseMessaging.unsubscribeFromTopic('manager_$managerId');
    debugPrint('Unsubscribed from manager_$managerId topic');
  }

  Future<void> subscribeToEmployeeTopic(String employeeId) async {
    await _firebaseMessaging.subscribeToTopic('employee_$employeeId');
    debugPrint('Subscribed to employee_$employeeId topic');
  }

  Future<void> unsubscribeFromEmployeeTopic(String employeeId) async {
    await _firebaseMessaging.unsubscribeFromTopic('employee_$employeeId');
    debugPrint('Unsubscribed from employee_$employeeId topic');
  }

  // Update user token on the server
  Future<void> updateTokenForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('fcm_token');

    if (token != null) {
      debugPrint("Updating FCM token for user $userId: $token");

      try {
        // Update token in Firestore
        await FirebaseFirestore.instance
            .collection('fcm_tokens')
            .doc(userId)
            .set({
          'token': token,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        debugPrint("Token updated successfully in Firestore");
      } catch (e) {
        debugPrint("Error updating token in Firestore: $e");

        // Try using Cloud Function as fallback
        try {
          final callable = FirebaseFunctions.instance.httpsCallable('storeUserFcmToken');
          final result = await callable.call({
            'userId': userId,
            'token': token,
          });

          debugPrint("Token updated via Cloud Function: ${result.data}");
        } catch (functionError) {
          debugPrint("Error updating token via Cloud Function: $functionError");
        }
      }
    }
  }

  // Test notification - useful for debugging
  Future<void> sendTestNotification(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      _channelId,
      'High Importance Notifications',
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
    DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
      payload: jsonEncode({'type': 'test'}),
    );

    debugPrint("Test notification sent");
  }

  // Clean up
  void dispose() {
    _notificationStreamController.close();
  }
}