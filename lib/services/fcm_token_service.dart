

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class FcmTokenService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Register token for the user
  Future<void> registerTokenForUser(String userId) async {
    try {
      // Request permission for notifications (iOS)
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,     // Important for high-priority notifications
        provisional: false,
      );

      debugPrint('User granted notification permission: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Get the token
        String? token = await _firebaseMessaging.getToken();

        if (token != null) {
          // Save token locally
          await _saveTokenLocally(token);

          debugPrint('FCM Token obtained: ${token.substring(0, 15)}...');

          // Upload to Firestore using multiple methods for redundancy
          // Original ID format
          bool success = await _updateTokenInFirestore(userId, token);

          // Try multiple ID formats for redundancy
          if (userId.startsWith('EMP')) {
            // Also try without EMP prefix
            String altId = userId.substring(3);
            await _updateTokenInFirestore(altId, token);
            debugPrint('Also registered token with alt ID: $altId');

            // Also register with topic subscription for better delivery
            await _firebaseMessaging.subscribeToTopic('employee_$altId');
            debugPrint('Subscribed to topic: employee_$altId');
          } else {
            // Also try with EMP prefix
            String altId = 'EMP$userId';
            await _updateTokenInFirestore(altId, token);
            debugPrint('Also registered token with alt ID: $altId');

            // Also register with topic subscription for better delivery
            await _firebaseMessaging.subscribeToTopic('employee_$altId');
            debugPrint('Subscribed to topic: employee_$altId');
          }

          // Always subscribe to employee topic
          await _firebaseMessaging.subscribeToTopic('employee_$userId');
          debugPrint('Subscribed to topic: employee_$userId');

          // Also subscribe to all employees topic
          await _firebaseMessaging.subscribeToTopic('all_employees');
          debugPrint('Subscribed to topic: all_employees');

          // Setup token refresh listener
          _setupTokenRefreshListener(userId);

          debugPrint('FCM Token registration completed for user: $userId');
        }
      } else {
        debugPrint('User declined notification permissions: ${settings.authorizationStatus}');
      }
    } catch (e) {
      debugPrint('Error registering FCM token: $e');
    }
  }

  // Save token locally for future reference
  Future<void> _saveTokenLocally(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);
    debugPrint('FCM Token saved locally: ${token.substring(0, 15)}...');
  }

  // Upload the token to Firestore
  Future<bool> _updateTokenInFirestore(String userId, String token) async {
    try {
      // First try direct Firestore update
      try {
        await FirebaseFirestore.instance.collection('fcm_tokens').doc(userId).set({
          'token': token,
          'updatedAt': FieldValue.serverTimestamp(),
          'platform': defaultTargetPlatform.toString(),
        });
        debugPrint('FCM token updated in Firestore for user: $userId');
        return true;
      } catch (e) {
        debugPrint('Direct Firestore update failed, trying Cloud Function: $e');
      }

      // If direct update fails, use the Cloud Function
      final callable = _functions.httpsCallable('storeUserFcmToken');

      final result = await callable.call({
        'userId': userId,
        'token': token,
      });

      debugPrint('Cloud Function result: ${result.data}');
      return true;
    } catch (e) {
      debugPrint('Error updating FCM token in Firestore: $e');
      return false;
    }
  }

  // Listen for token refreshes
  void _setupTokenRefreshListener(String userId) {
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      debugPrint('FCM Token refreshed. Updating for user: $userId');
      _saveTokenLocally(newToken);
      _updateTokenInFirestore(userId, newToken);

      // Also try with alternative ID format
      if (userId.startsWith('EMP')) {
        _updateTokenInFirestore(userId.substring(3), newToken);
      } else {
        _updateTokenInFirestore('EMP$userId', newToken);
      }
    });
  }

  // Subscribe to topics
  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
    debugPrint('Subscribed to topic: $topic');
  }

  // Unsubscribe from topics
  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
    debugPrint('Unsubscribed from topic: $topic');
  }

  // Subscribe manager to both formats of manager ID
  Future<void> subscribeManagerToAllFormats(String managerId) async {
    try {
      // Subscribe to standard format
      await subscribeToTopic('manager_$managerId');
      debugPrint('Manager subscribed to topic: manager_$managerId');

      // Also subscribe to alternative format
      String altId;
      if (managerId.startsWith('EMP')) {
        altId = managerId.substring(3);
      } else {
        altId = 'EMP$managerId';
      }

      await subscribeToTopic('manager_$altId');
      debugPrint('Manager also subscribed to topic: manager_$altId');

      // Also subscribe to all managers topic
      await subscribeToTopic('all_managers');
      debugPrint('Manager subscribed to topic: all_managers');

      // Store subscription information in Firestore for reference
      await FirebaseFirestore.instance.collection('fcm_subscriptions').doc(managerId).set({
        'topics': ['manager_$managerId', 'manager_$altId', 'all_managers'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error subscribing manager to topics: $e');
    }
  }

  // Get the currently stored FCM token
  Future<String?> getStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('fcm_token');
  }

  // Clear stored token (useful for logging out)
  Future<void> clearStoredToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('fcm_token');
    debugPrint('FCM Token cleared from local storage');
  }

  // Force re-registration of token (useful for troubleshooting)
  Future<void> forceTokenRefresh(String userId) async {
    try {
      // Delete existing token to force refresh
      await _firebaseMessaging.deleteToken();
      debugPrint('Deleted existing FCM token');

      // Get a new token
      String? newToken = await _firebaseMessaging.getToken();

      if (newToken != null) {
        await _saveTokenLocally(newToken);
        await _updateTokenInFirestore(userId, newToken);

        // Also update alternative ID format
        if (userId.startsWith('EMP')) {
          await _updateTokenInFirestore(userId.substring(3), newToken);
        } else {
          await _updateTokenInFirestore('EMP$userId', newToken);
        }

        debugPrint('Successfully forced FCM token refresh for user: $userId');
      }
    } catch (e) {
      debugPrint('Error forcing token refresh: $e');
    }
  }
}