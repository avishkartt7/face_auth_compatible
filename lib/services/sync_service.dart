// lib/services/sync_service.dart - Fixed version

import 'dart:async';
import 'package:face_auth_compatible/repositories/attendance_repository.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';

class SyncService {
  final ConnectivityService _connectivityService;
  final AttendanceRepository _attendanceRepository;

  Timer? _syncTimer;
  bool _isSyncing = false;
  StreamSubscription<ConnectionStatus>? _connectivitySubscription;

  SyncService({
    required ConnectivityService connectivityService,
    required AttendanceRepository attendanceRepository,
  }) : _connectivityService = connectivityService,
        _attendanceRepository = attendanceRepository {
    // Initialize sync service when created
    initialize();
  }

  // Initialize sync service
  void initialize() {
    print("Initializing SyncService");

    // Listen for connectivity changes
    _connectivitySubscription = _connectivityService.connectionStatusStream.listen((status) {
      print("SyncService: Connectivity changed to: $status");

      if (status == ConnectionStatus.online) {
        // When coming back online, perform sync after a short delay
        // This delay allows other services to stabilize
        Future.delayed(const Duration(seconds: 2), () {
          print("SyncService: Coming online, attempting sync...");
          syncData();
        });
      }
    });

    // Set up periodic sync every 5 minutes (reduced from 15 for testing)
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        print("SyncService: Periodic sync triggered");
        syncData();
      }
    });

    // Perform initial sync if online
    if (_connectivityService.currentStatus == ConnectionStatus.online) {
      Future.delayed(const Duration(seconds: 1), () {
        syncData();
      });
    }
  }

  // Sync all pending data
  Future<void> syncData() async {
    if (_isSyncing) {
      print("SyncService: Already syncing, skipping...");
      return;
    }

    if (_connectivityService.currentStatus == ConnectionStatus.offline) {
      print("SyncService: Cannot sync while offline");
      return;
    }

    _isSyncing = true;
    print("SyncService: Starting sync...");

    try {
      // Get pending records count
      final pendingRecords = await _attendanceRepository.getPendingRecords();
      print("SyncService: Found ${pendingRecords.length} pending records");

      if (pendingRecords.isNotEmpty) {
        bool success = await _attendanceRepository.syncPendingRecords();
        print("SyncService: Sync ${success ? 'successful' : 'failed'}");
      }

      // You could add other sync operations here
      // For example: sync user profiles, locations, etc.

    } catch (e) {
      print('SyncService: Error during sync: $e');
    } finally {
      _isSyncing = false;
      print("SyncService: Sync completed");
    }
  }

  // Manual sync trigger for user-initiated sync
  Future<bool> manualSync() async {
    print("SyncService: Manual sync requested");

    if (_connectivityService.currentStatus == ConnectionStatus.offline) {
      print("SyncService: Cannot sync while offline");
      return false;
    }

    if (_isSyncing) {
      print("SyncService: Already syncing");
      return false;
    }

    _isSyncing = true;

    try {
      final success = await _attendanceRepository.syncPendingRecords();
      _isSyncing = false;
      print("SyncService: Manual sync ${success ? 'successful' : 'failed'}");
      return success;
    } catch (e) {
      _isSyncing = false;
      print("SyncService: Manual sync error: $e");
      return false;
    }
  }

  void dispose() {
    print("SyncService: Disposing...");
    _syncTimer?.cancel();
    _connectivitySubscription?.cancel();
  }
}