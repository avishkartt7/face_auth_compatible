// lib/services/sync_service.dart

import 'dart:async';
import 'package:face_auth_compatible/repositories/attendance_repository.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';

class SyncService {
  final ConnectivityService _connectivityService;
  final AttendanceRepository _attendanceRepository;

  Timer? _syncTimer;
  bool _isSyncing = false;

  SyncService({
    required ConnectivityService connectivityService,
    required AttendanceRepository attendanceRepository,
  }) : _connectivityService = connectivityService,
        _attendanceRepository = attendanceRepository;

  // Initialize sync service
  void initialize() {
    // Listen for connectivity changes
    _connectivityService.connectionStatusStream.listen((status) {
      if (status == ConnectionStatus.online) {
        // When coming back online, perform sync
        syncData();
      }
    });

    // Set up periodic sync every 15 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        syncData();
      }
    });
  }

  // Sync all pending data
  Future<void> syncData() async {
    if (_isSyncing || _connectivityService.currentStatus == ConnectionStatus.offline) {
      return;
    }

    _isSyncing = true;

    try {
      await _attendanceRepository.syncPendingRecords();
      // You could add other sync operations here
    } catch (e) {
      print('Error during sync: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // Manual sync trigger for user-initiated sync
  Future<bool> manualSync() async {
    if (_connectivityService.currentStatus == ConnectionStatus.offline) {
      return false;
    }

    if (_isSyncing) {
      return false; // Already syncing
    }

    _isSyncing = true;

    try {
      await _attendanceRepository.syncPendingRecords();
      _isSyncing = false;
      return true;
    } catch (e) {
      _isSyncing = false;
      return false;
    }
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}