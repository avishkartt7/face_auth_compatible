// lib/services/notification_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  // Stream controller for handling notification taps
  final StreamController<Map<String, dynamic>> _notificationStreamController =
  StreamController<Map<String, dynamic>>.broadcast();

  // Expose stream for listening to notification taps
  Stream<Map<String, dynamic>> get notificationStream => _notificationStreamController.stream;

  NotificationService() {
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    // Request permission for iOS
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print('User granted permission: ${settings.authorizationStatus}');

    // Get the token
    String? token = await _firebaseMessaging.getToken();
    _saveToken(token);

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

    // Handle when the app is terminated and opened from a notification
    await _checkForInitialMessage();
  }

  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    final Map<String, dynamic> payload =
    jsonDecode(response.payload ?? '{}') as Map<String, dynamic>;
    _notificationStreamController.add(payload);
  }

  Future<void> _checkForInitialMessage() async {
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();

    if (initialMessage != null) {
      _handleBackgroundMessage(initialMessage);
    }
  }

  Future<void> _saveToken(String? token) async {
    if (token == null) return;

    print('FCM Token: $token');

    // Save the token to shared preferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);

    // TODO: Send the token to your server to associate it with the user
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('Got a message whilst in the foreground!');
    print('Message data: ${message.data}');

    if (message.notification != null) {
      print('Message also contained a notification: ${message.notification}');
      await _showLocalNotification(message);
    }
  }

  void _handleBackgroundMessage(RemoteMessage message) {
    print('Handling a background message: ${message.messageId}');

    // Add to stream controller to navigate if needed
    if (message.data.isNotEmpty) {
      _notificationStreamController.add(message.data);
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null) {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        'check_out_approvals_channel',
        'Check-out Approvals',
        channelDescription: 'Notifications about check-out approval requests',
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
        notification.hashCode,
        notification.title,
        notification.body,
        platformChannelSpecifics,
        payload: jsonEncode(message.data),
      );
    }
  }

  // Subscribe to topics for targeted notifications
  Future<void> subscribeToManagerTopic(String managerId) async {
    await _firebaseMessaging.subscribeToTopic('manager_$managerId');
    print('Subscribed to manager_$managerId topic');
  }

  Future<void> unsubscribeFromManagerTopic(String managerId) async {
    await _firebaseMessaging.unsubscribeFromTopic('manager_$managerId');
    print('Unsubscribed from manager_$managerId topic');
  }

  Future<void> subscribeToEmployeeTopic(String employeeId) async {
    await _firebaseMessaging.subscribeToTopic('employee_$employeeId');
    print('Subscribed to employee_$employeeId topic');
  }

  Future<void> unsubscribeFromEmployeeTopic(String employeeId) async {
    await _firebaseMessaging.unsubscribeFromTopic('employee_$employeeId');
    print('Unsubscribed from employee_$employeeId topic');
  }

  // Update user token on the server
  Future<void> updateTokenForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('fcm_token');

    if (token != null) {
      // TODO: Update your server with the token
      // This will depend on your backend implementation
    }
  }

  // Clean up
  void dispose() {
    _notificationStreamController.close();
  }
}