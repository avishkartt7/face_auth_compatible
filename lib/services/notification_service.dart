
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
    try {
      debugPrint("NotificationService: Initializing notifications");

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
      if (token != null) {
        debugPrint('FCM Token obtained: ${token.substring(0, 10)}...');
        await _saveToken(token);
      } else {
        debugPrint('Failed to get FCM token');
      }

      // Listen for token refreshes
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        debugPrint('FCM Token refreshed: ${newToken.substring(0, 10)}...');
        _saveToken(newToken);
      });

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
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('======= RECEIVED FOREGROUND MESSAGE =======');
        debugPrint('Message ID: ${message.messageId}');
        debugPrint('Notification: ${message.notification?.title}');
        debugPrint('Data: ${message.data}');

        _handleForegroundMessage(message);
      });

      // Handle when a notification is tapped and the app is in the background
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        debugPrint('======= APP OPENED FROM BACKGROUND MESSAGE =======');
        debugPrint('Message ID: ${message.messageId}');
        debugPrint('Notification: ${message.notification?.title}');
        debugPrint('Data: ${message.data}');

        _handleBackgroundMessage(message);
      });

      // Enable foreground notifications on iOS
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,   // Required to show alert
        badge: true,   // Required to update badge
        sound: true,   // Required to play sound
      );

      // Handle when the app is terminated and opened from a notification
      await _checkForInitialMessage();

      debugPrint("Notification service initialized successfully");
    } catch (e) {
      debugPrint("Error initializing notification service: $e");
    }
  }

  // Create notification channels for Android
  Future<void> _createNotificationChannels() async {
    try {
      debugPrint("Creating notification channels for Android");

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

      debugPrint("Android notification channels created successfully");
    } catch (e) {
      debugPrint("Error creating notification channels: $e");
    }
  }

  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    try {
      debugPrint("Local notification tapped: ${response.id}");
      debugPrint("Payload: ${response.payload}");

      final Map<String, dynamic> payload = response.payload != null && response.payload!.isNotEmpty
          ? jsonDecode(response.payload!) as Map<String, dynamic>
          : {};

      // Add flag to indicate this is from a notification tap
      payload['fromNotificationTap'] = 'true';

      _notificationStreamController.add(payload);

      debugPrint("Notification payload added to stream");
    } catch (e) {
      debugPrint("Error processing notification response: $e");
    }
  }

  Future<void> _checkForInitialMessage() async {
    try {
      // Check if app was opened from a notification when it was terminated
      RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();

      if (initialMessage != null) {
        debugPrint("App opened from terminated state with notification: ${initialMessage.messageId}");
        debugPrint("Initial message notification: ${initialMessage.notification?.title}");
        debugPrint("Initial message data: ${initialMessage.data}");

        // Add a flag to indicate this is from initial notification
        final Map<String, dynamic> data = Map<String, dynamic>.from(initialMessage.data);
        data['fromNotificationTap'] = 'true';
        data['fromInitialMessage'] = 'true';

        _notificationStreamController.add(data);

        debugPrint("Initial message added to notification stream");
      } else {
        debugPrint("No initial message found");
      }
    } catch (e) {
      debugPrint("Error checking for initial message: $e");
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      debugPrint('Saving FCM Token: ${token.substring(0, 10)}...');

      // Save the token to shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);

      debugPrint("Token saved to shared preferences");
    } catch (e) {
      debugPrint("Error saving token: $e");
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    try {
      debugPrint('Processing foreground message: ${message.messageId}');

      // Always add to the stream for app logic to handle
      if (message.data.isNotEmpty) {
        final data = Map<String, dynamic>.from(message.data);
        _notificationStreamController.add(data);
        debugPrint('Message data added to stream: ${data['type']}');
      }

      if (message.notification != null) {
        debugPrint('Message has notification: ${message.notification?.title}');

        // Determine the notification channel based on the request type
        String channelId = _channelId; // Default channel
        String channelName = 'High Importance Notifications';
        String channelDescription = 'This channel is used for important notifications.';

        // Check if it's a check-in/check-out related notification
        if (message.data.containsKey('type')) {
          final notificationType = message.data['type'];
          debugPrint('Notification type: $notificationType');

          if (notificationType == 'check_out_request_update' ||
              notificationType == 'new_check_out_request') {
            // Use specific channel for check-in/check-out requests
            channelId = _channelIdCheckRequests;
            channelName = 'Check Requests';
            channelDescription = 'Notifications about check-in and check-out approval requests';
            debugPrint('Using check requests channel');
          }
        }

        await _showLocalNotification(
          message,
          channelId,
          channelName,
          channelDescription
        );
      } else {
        debugPrint('Message does not contain notification, only data');
      }
    } catch (e) {
      debugPrint("Error handling foreground message: $e");
    }
  }

  void _handleBackgroundMessage(RemoteMessage message) {
    try {
      debugPrint('Handling background message: ${message.messageId}');

      // Add to stream controller to navigate if needed
      if (message.data.isNotEmpty) {
        // Add a flag to indicate this is from a background message
        final Map<String, dynamic> data = Map<String, dynamic>.from(message.data);
        data['fromNotificationTap'] = 'true';
        data['fromBackgroundMessage'] = 'true';

        _notificationStreamController.add(data);
        debugPrint('Background message data added to stream');
      }
    } catch (e) {
      debugPrint("Error handling background message: $e");
    }
  }

  Future<void> _showLocalNotification(
      RemoteMessage message,
      String channelId,
      String channelName,
      String channelDescription
      ) async {
    try {
      final notification = message.notification;
      final android = message.notification?.android;

      if (notification != null) {
        debugPrint('Creating local notification: ${notification.title}');

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
    } catch (e) {
      debugPrint("Error showing local notification: $e");
    }
  }

  // Subscribe to topics for targeted notifications
  Future<void> subscribeToManagerTopic(String managerId) async {
    try {
      // Subscribe to main topic format
      await _firebaseMessaging.subscribeToTopic('manager_$managerId');
      debugPrint('Subscribed to manager_$managerId topic');

      // Also subscribe to alternative format for redundancy
      if (managerId.startsWith('EMP')) {
        // Also subscribe without EMP prefix
        await _firebaseMessaging.subscribeToTopic('manager_${managerId.substring(3)}');
        debugPrint('Also subscribed to manager_${managerId.substring(3)} topic');
      } else {
        // Also subscribe with EMP prefix
        await _firebaseMessaging.subscribeToTopic('manager_EMP$managerId');
        debugPrint('Also subscribed to manager_EMP$managerId topic');
      }

      // Subscribe to all managers topic
      await _firebaseMessaging.subscribeToTopic('all_managers');
      debugPrint('Subscribed to all_managers topic');

      // Record subscription in Firestore for reference
      try {
        await FirebaseFirestore.instance.collection('fcm_subscriptions').doc(managerId).set({
          'topics': [
            'manager_$managerId',
            managerId.startsWith('EMP') ? 'manager_${managerId.substring(3)}' : 'manager_EMP$managerId',
            'all_managers'
          ],
          'updatedAt': FieldValue.serverTimestamp(),
          'isManager': true
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error recording subscription in Firestore: $e');
      }
    } catch (e) {
      debugPrint('Error subscribing to manager topics: $e');
    }
  }

  Future<void> unsubscribeFromManagerTopic(String managerId) async {
    try {
      // Try to unsubscribe from all possible formats
      await _firebaseMessaging.unsubscribeFromTopic('manager_$managerId');
      debugPrint('Unsubscribed from manager_$managerId topic');

      // Also unsubscribe from alternative format
      if (managerId.startsWith('EMP')) {
        await _firebaseMessaging.unsubscribeFromTopic('manager_${managerId.substring(3)}');
        debugPrint('Unsubscribed from manager_${managerId.substring(3)} topic');
      } else {
        await _firebaseMessaging.unsubscribeFromTopic('manager_EMP$managerId');
        debugPrint('Unsubscribed from manager_EMP$managerId topic');
      }

      // Keep all_managers subscription unless explicitly requested
    } catch (e) {
      debugPrint('Error unsubscribing from manager topics: $e');
    }
  }

  Future<void> subscribeToEmployeeTopic(String employeeId) async {
    try {
      // Subscribe to main topic format
      await _firebaseMessaging.subscribeToTopic('employee_$employeeId');
      debugPrint('Subscribed to employee_$employeeId topic');

      // Also subscribe to alternative format for redundancy
      if (employeeId.startsWith('EMP')) {
        // Also subscribe without EMP prefix
        await _firebaseMessaging.subscribeToTopic('employee_${employeeId.substring(3)}');
        debugPrint('Also subscribed to employee_${employeeId.substring(3)} topic');
      } else {
        // Also subscribe with EMP prefix
        await _firebaseMessaging.subscribeToTopic('employee_EMP$employeeId');
        debugPrint('Also subscribed to employee_EMP$employeeId topic');
      }

      // Subscribe to all employees topic
      await _firebaseMessaging.subscribeToTopic('all_employees');
      debugPrint('Subscribed to all_employees topic');

      // Record subscription in Firestore for reference
      try {
        await FirebaseFirestore.instance.collection('fcm_subscriptions').doc(employeeId).set({
          'topics': [
            'employee_$employeeId',
            employeeId.startsWith('EMP') ? 'employee_${employeeId.substring(3)}' : 'employee_EMP$employeeId',
            'all_employees'
          ],
          'updatedAt': FieldValue.serverTimestamp(),
          'isEmployee': true
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Error recording subscription in Firestore: $e');
      }
    } catch (e) {
      debugPrint('Error subscribing to employee topics: $e');
    }
  }

  Future<void> unsubscribeFromEmployeeTopic(String employeeId) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic('employee_$employeeId');
      debugPrint('Unsubscribed from employee_$employeeId topic');

      // Also unsubscribe from alternative format
      if (employeeId.startsWith('EMP')) {
        await _firebaseMessaging.unsubscribeFromTopic('employee_${employeeId.substring(3)}');
        debugPrint('Unsubscribed from employee_${employeeId.substring(3)} topic');
      } else {
        await _firebaseMessaging.unsubscribeFromTopic('employee_EMP$employeeId');
        debugPrint('Unsubscribed from employee_EMP$employeeId topic');
      }
    } catch (e) {
      debugPrint('Error unsubscribing from employee topics: $e');
    }
  }

  // Update user token on the server
  Future<void> updateTokenForUser(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('fcm_token');

      if (token != null) {
        debugPrint("Updating FCM token for user $userId: ${token.substring(0, 10)}...");

        try {
          // Update token in Firestore
          await FirebaseFirestore.instance
              .collection('fcm_tokens')
              .doc(userId)
              .set({
            'token': token,
            'updatedAt': FieldValue.serverTimestamp(),
            'platform': defaultTargetPlatform.toString(),
          });

          // Also try alternative ID format
          if (userId.startsWith('EMP')) {
            await FirebaseFirestore.instance
                .collection('fcm_tokens')
                .doc(userId.substring(3))
                .set({
              'token': token,
              'updatedAt': FieldValue.serverTimestamp(),
              'platform': defaultTargetPlatform.toString(),
            });
          } else {
            await FirebaseFirestore.instance
                .collection('fcm_tokens')
                .doc('EMP$userId')
                .set({
              'token': token,
              'updatedAt': FieldValue.serverTimestamp(),
              'platform': defaultTargetPlatform.toString(),
            });
          }

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
      } else {
        debugPrint("No FCM token found to update");
      }
    } catch (e) {
      debugPrint("Error in updateTokenForUser: $e");
    }
  }

  // Test notification - useful for debugging
  Future<void> sendTestNotification(String title, String body) async {
    try {
      debugPrint("Sending test notification: $title");

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

      debugPrint("Test notification sent successfully");
    } catch (e) {
      debugPrint("Error sending test notification: $e");
    }
  }

  // Force refresh FCM token and update in Firestore
  Future<void> refreshToken(String userId) async {
    try {
      debugPrint("Forcing FCM token refresh for user: $userId");

      // Delete the current token to force a refresh
      await _firebaseMessaging.deleteToken();
      debugPrint("Deleted current FCM token");

      // Request a new token
      final newToken = await _firebaseMessaging.getToken();
      if (newToken != null) {
        debugPrint("Got new FCM token: ${newToken.substring(0, 10)}...");

        // Save locally
        await _saveToken(newToken);

        // Update in Firestore with both possible formats
        await FirebaseFirestore.instance
            .collection('fcm_tokens')
            .doc(userId)
            .set({
          'token': newToken,
          'updatedAt': FieldValue.serverTimestamp(),
          'platform': defaultTargetPlatform.toString(),
          'refreshed': true,
        });

        // Also try alternative ID format
        if (userId.startsWith('EMP')) {
          await FirebaseFirestore.instance
              .collection('fcm_tokens')
              .doc(userId.substring(3))
              .set({
            'token': newToken,
            'updatedAt': FieldValue.serverTimestamp(),
            'platform': defaultTargetPlatform.toString(),
            'refreshed': true,
          });
        } else {
          await FirebaseFirestore.instance
              .collection('fcm_tokens')
              .doc('EMP$userId')
              .set({
            'token': newToken,
            'updatedAt': FieldValue.serverTimestamp(),
            'platform': defaultTargetPlatform.toString(),
            'refreshed': true,
          });
        }

        debugPrint("Token refresh completed and updated in Firestore");
      } else {
        debugPrint("Failed to get new FCM token");
      }
    } catch (e) {
      debugPrint("Error refreshing FCM token: $e");
    }
  }

  // Clean up
  void dispose() {
    _notificationStreamController.close();
  }
}