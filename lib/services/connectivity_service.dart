// lib/services/connectivity_service.dart - Improved version

import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum ConnectionStatus {
  online,
  offline
}

class ConnectivityService {
  // Create a stream controller to broadcast connectivity status
  final _connectionStatusController = StreamController<ConnectionStatus>.broadcast();

  // Public stream that widgets can listen to
  Stream<ConnectionStatus> get connectionStatusStream => _connectionStatusController.stream;

  // Store the current connection status
  ConnectionStatus _currentStatus = ConnectionStatus.online;

  // Flag to override connection status for testing
  bool _testOverrideOffline = false;

  // Getter that respects the test override
  ConnectionStatus get currentStatus {
    if (_testOverrideOffline) {
      return ConnectionStatus.offline;
    }
    return _currentStatus;
  }

  ConnectivityService() {
    // Initialize connectivity checking
    Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      // Only update if we're not in test override mode
      if (!_testOverrideOffline) {
        _performConnectivityCheck(result);
      }
    });

    // Check initial connection state
    _checkInitialConnection();
  }

  Future<void> _checkInitialConnection() async {
    final ConnectivityResult result = await Connectivity().checkConnectivity();
    _performConnectivityCheck(result);
  }

  Future<void> _performConnectivityCheck(ConnectivityResult connectivityResult) async {
    // First, check if device thinks it has connectivity
    if (connectivityResult == ConnectivityResult.none) {
      _updateStatus(ConnectionStatus.offline);
      return;
    }

    // Next, try a more reliable internet check
    bool hasRealConnection = await _hasActualInternetConnection();

    _updateStatus(hasRealConnection ? ConnectionStatus.online : ConnectionStatus.offline);
  }

  Future<bool> _hasActualInternetConnection() async {
    try {
      // Try to reach a reliable host with a short timeout
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));

      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        // Double check with a service we use in the app
        try {
          await FirebaseFirestore.instance
              .collection('test')
              .doc('test')
              .get()
              .timeout(const Duration(seconds: 3));
          return true;
        } catch (e) {
          print("Firebase check failed but internet appears available: $e");
          // Still return true if we can reach google but not Firebase
          // This allows the app to work in online mode even if Firebase has issues
          return true;
        }
      }
      return false;
    } on SocketException catch (e) {
      print("Socket exception during connectivity check: $e");
      return false;
    } on TimeoutException catch (e) {
      print("Timeout during connectivity check: $e");
      return false;
    } catch (e) {
      print("Unknown error during connectivity check: $e");
      return false;
    }
  }

  void _updateStatus(ConnectionStatus newStatus) {
    if (_currentStatus != newStatus) {
      print("Connectivity status changed from $_currentStatus to $newStatus");
      _currentStatus = newStatus;
      // Broadcast the new status
      _connectionStatusController.add(_currentStatus);
    }
  }

  // Force check connectivity - call this when user manually refreshes
  Future<bool> checkConnectivity() async {
    if (_testOverrideOffline) {
      return false;
    }

    final result = await _hasActualInternetConnection();
    _updateStatus(result ? ConnectionStatus.online : ConnectionStatus.offline);
    return result;
  }

  // Method to simulate offline mode for testing
  void setOfflineModeForTesting(bool isOffline) {
    _testOverrideOffline = isOffline;

    if (_testOverrideOffline) {
      // Force offline status
      _connectionStatusController.add(ConnectionStatus.offline);
    } else {
      // Restore actual connection status
      _checkInitialConnection();
    }

    // Log the change
    print('Connectivity status override set to offline: $_testOverrideOffline');
  }

  // Method to check if we're in testing mode
  bool isInTestMode() {
    return _testOverrideOffline;
  }

  void dispose() {
    _connectionStatusController.close();
  }
}