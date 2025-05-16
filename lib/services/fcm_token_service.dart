// lib/services/fcm_token_service.dart
// Complete implementation with fixed return type error

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

          // Upload to Firestore using multiple methods for redundancy
          bool success = await _updateTokenInFirestore(userId, token);

          // Also try with alternative ID format
          if (userId.startsWith('EMP')) {
            await _updateTokenInFirestore(userId.substring(3), token);
          } else {
            await _updateTokenInFirestore('EMP$userId', token);
          }

          // Setup token refresh listener
          setupTokenRefreshListener(userId);

          debugPrint('FCM Token registered for user: $userId, token: ${token.substring(0, 10)}...');

          // Don't return the token
        }
      } else {
        debugPrint('User declined notification permissions: ${settings.authorizationStatus}');
      }
    } catch (e) {
      debugPrint('Error registering FCM token: $e');
    }

    // Don't return anything, just complete the Future
    return;
  }

  // Save token locally for future reference
  Future<void> _saveTokenLocally(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);
  }

  // Upload the token to Firestore
  Future<bool> _updateTokenInFirestore(String userId, String token) async {
    try {
      // First try direct Firestore update
      try {
        await FirebaseFirestore.instance.collection('fcm_tokens').doc(userId).set({
          'token': token,
          'updatedAt': FieldValue.serverTimestamp(),
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
  void setupTokenRefreshListener(String userId) {
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
    // Subscribe to standard format
    await subscribeToTopic('manager_$managerId');

    // Also subscribe to alternative format
    if (managerId.startsWith('EMP')) {
      await subscribeToTopic('manager_${managerId.substring(3)}');
    } else {
      await subscribeToTopic('manager_EMP$managerId');
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
  }
}