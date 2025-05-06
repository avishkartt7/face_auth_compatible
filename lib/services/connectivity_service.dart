// lib/services/connectivity_service.dart

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

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
        _updateConnectionStatus(result);
      }
    });

    // Check initial connection state
    _checkInitialConnection();
  }

  Future<void> _checkInitialConnection() async {
    final ConnectivityResult result = await Connectivity().checkConnectivity();
    _updateConnectionStatus(result);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    if (result == ConnectivityResult.none) {
      _currentStatus = ConnectionStatus.offline;
    } else {
      _currentStatus = ConnectionStatus.online;
    }

    // Broadcast the new status
    _connectionStatusController.add(_currentStatus);
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