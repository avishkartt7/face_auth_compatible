// lib/services/fcm_token_service.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
      );

      print('User granted notification permission: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        // Get the token
        String? token = await _firebaseMessaging.getToken();

        if (token != null) {
          // Save token locally
          await _saveTokenLocally(token);

          // Upload to Firestore using Cloud Function
          await _updateTokenInFirestore(userId, token);

          print('FCM Token registered for user: $userId');
        }
      }
    } catch (e) {
      print('Error registering FCM token: $e');
    }
  }

  // Save token locally for future reference
  Future<void> _saveTokenLocally(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);
  }

  // Upload the token to Firestore
  Future<void> _updateTokenInFirestore(String userId, String token) async {
    try {
      // First try direct Firestore update
      try {
        await FirebaseFirestore.instance.collection('fcm_tokens').doc(userId).set({
          'token': token,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      } catch (e) {
        print('Direct Firestore update failed, trying Cloud Function: $e');
      }

      // If direct update fails, use the Cloud Function
      final HttpsCallable callable = _functions.httpsCallable('storeUserFcmToken');

      final result = await callable.call({
        'userId': userId,
        'token': token,
      });

      print('Cloud Function result: ${result.data}');
    } catch (e) {
      print('Error updating FCM token in Firestore: $e');
    }
  }

  // Listen for token refreshes
  void setupTokenRefreshListener(String userId) {
    _firebaseMessaging.onTokenRefresh.listen((newToken) {
      _saveTokenLocally(newToken);
      _updateTokenInFirestore(userId, newToken);
      print('FCM Token refreshed for user: $userId');
    });
  }

  // Subscribe to topics
  Future<void> subscribeToTopic(String topic) async {
    await _firebaseMessaging.subscribeToTopic(topic);
    print('Subscribed to topic: $topic');
  }

  // Unsubscribe from topics
  Future<void> unsubscribeFromTopic(String topic) async {
    await _firebaseMessaging.unsubscribeFromTopic(topic);
    print('Unsubscribed from topic: $topic');
  }
}