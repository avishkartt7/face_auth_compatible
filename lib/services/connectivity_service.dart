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
  ConnectionStatus get currentStatus => _currentStatus;

  ConnectivityService() {
    // Initialize connectivity checking
    Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      _updateConnectionStatus(result);
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

  void dispose() {
    _connectionStatusController.close();
  }
}