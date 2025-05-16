// lib/repositories/attendance_repository.dart - Fixed version

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/model/local_attendance_model.dart';
import 'package:face_auth_compatible/services/database_helper.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

class AttendanceRepository {
  final DatabaseHelper _dbHelper;
  final FirebaseFirestore _firestore;
  final ConnectivityService _connectivityService;

  AttendanceRepository({
    required DatabaseHelper dbHelper,
    FirebaseFirestore? firestore,
    required ConnectivityService connectivityService,
  }) : _dbHelper = dbHelper,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _connectivityService = connectivityService;

  // Record check-in that works both online and offline
  Future<bool> recordCheckIn({
    required String employeeId,
    required DateTime checkInTime,
    required String locationId,
    required String locationName,
    required double locationLat,
    required double locationLng,
    String? imageData,
  }) async {
    try {
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      print("AttendanceRepository: Recording check-in for $employeeId on $today");

      // First, clear any existing records for today (to handle duplicates)
      try {
        await _dbHelper.delete(
          'attendance',
          where: 'employee_id = ? AND date = ?',
          whereArgs: [employeeId, today],
        );
        print("AttendanceRepository: Cleared any existing records for today");
      } catch (deleteError) {
        print("AttendanceRepository: Error clearing existing records: $deleteError");
      }

      // Prepare check-in data
      Map<String, dynamic> checkInData = {
        'date': today,
        'checkIn': checkInTime.toIso8601String(),
        'checkOut': null,
        'workStatus': 'In Progress',
        'totalHours': 0,
        'location': locationName,
        'locationId': locationId,
        'locationLat': locationLat,
        'locationLng': locationLng,
        'isWithinGeofence': true,
      };

      // Create local record
      LocalAttendanceRecord localRecord = LocalAttendanceRecord(
        employeeId: employeeId,
        date: today,
        checkIn: checkInTime.toIso8601String(),
        locationId: locationId,
        isSynced: false,
        rawData: checkInData,
      );

      // Save to local database
      int localId = await _dbHelper.insert('attendance', localRecord.toMap());
      print("AttendanceRepository: Check-in saved locally with ID: $localId");

      // If online, try to save to Firestore
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        try {
          await _firestore
              .collection('employees')
              .doc(employeeId)
              .collection('attendance')
              .doc(today)
              .set({
            ...checkInData,
            'checkIn': Timestamp.fromDate(checkInTime),
          }, SetOptions(merge: true));

          // Mark as synced
          await _dbHelper.update(
            'attendance',
            {'is_synced': 1},
            where: 'id = ?',
            whereArgs: [localId],
          );

          print("AttendanceRepository: Check-in saved to Firestore and marked as synced");
        } catch (e) {
          print("AttendanceRepository: Error saving to Firestore: $e");
          // Continue - local save was successful
        }
      }

      return true;
    } catch (e) {
      print('AttendanceRepository: Error recording check-in: $e');
      return false;
    }
  }

  // Record check-out that works both online and offline
  Future<bool> recordCheckOut({
    required String employeeId,
    required DateTime checkOutTime,
  }) async {
    try {
      // Format today's date
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      print("AttendanceRepository: Recording check-out for $employeeId on $today");

      // First, check if we have a local record
      List<Map<String, dynamic>> localRecords = await _dbHelper.query(
        'attendance',
        where: 'employee_id = ? AND date = ?',
        whereArgs: [employeeId, today],
      );

      if (localRecords.isEmpty) {
        print("AttendanceRepository: No check-in record found for today");
        return false; // No check-in record found
      }

      // Get the local record and update it
      LocalAttendanceRecord record = LocalAttendanceRecord.fromMap(localRecords.first);

      // Ensure there's a check-in time
      if (record.checkIn == null) {
        print("AttendanceRepository: No check-in time in record");
        return false;
      }

      DateTime checkInTime = DateTime.parse(record.checkIn!);

      // Calculate working hours
      double hoursWorked = checkOutTime.difference(checkInTime).inMinutes / 60;
      print("AttendanceRepository: Hours worked: ${hoursWorked.toStringAsFixed(2)}");

      // Update the raw data
      Map<String, dynamic> updatedData = Map<String, dynamic>.from(record.rawData);
      updatedData['checkOut'] = checkOutTime.toIso8601String();
      updatedData['workStatus'] = 'Completed';
      updatedData['totalHours'] = hoursWorked;

      // Determine sync status based on connectivity
      bool shouldSync = _connectivityService.currentStatus == ConnectionStatus.online;

      // Prepare the updated local record
      LocalAttendanceRecord updatedRecord = LocalAttendanceRecord(
        id: record.id,
        employeeId: employeeId,
        date: today,
        checkIn: record.checkIn,
        checkOut: checkOutTime.toIso8601String(),
        locationId: record.locationId,
        isSynced: false, // Always mark as unsynced initially
        rawData: updatedData,
      );

      // Update local record first
      await _dbHelper.update(
        'attendance',
        updatedRecord.toMap(),
        where: 'id = ?',
        whereArgs: [record.id],
      );
      print("AttendanceRepository: Local record updated");

      // If online, try to update Firestore
      if (shouldSync) {
        try {
          await _firestore
              .collection('employees')
              .doc(employeeId)
              .collection('attendance')
              .doc(today)
              .set({
            'checkOut': Timestamp.fromDate(checkOutTime),
            'workStatus': 'Completed',
            'totalHours': hoursWorked,
          }, SetOptions(merge: true));

          print("AttendanceRepository: Firestore updated successfully");

          // Mark as synced in local database
          await _dbHelper.update(
            'attendance',
            {'is_synced': 1},
            where: 'id = ?',
            whereArgs: [record.id],
          );
        } catch (e) {
          print("AttendanceRepository: Error updating Firestore: $e");
          // Continue - local update was successful
        }
      } else {
        print("AttendanceRepository: Offline mode - record marked for sync");
      }

      return true;
    } catch (e) {
      print('AttendanceRepository: Error recording check-out: $e');
      return false;
    }
  }

  // Get today's attendance record
  // Get today's attendance record
  Future<LocalAttendanceRecord?> getTodaysAttendance(String employeeId) async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      // Always check local database first
      List<Map<String, dynamic>> records = await _dbHelper.query(
        'attendance',
        where: 'employee_id = ? AND date = ?',
        whereArgs: [employeeId, today],
      );

      if (records.isNotEmpty) {
        return LocalAttendanceRecord.fromMap(records.first);
      }

      // If online and no local record, check Firestore
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        final doc = await _firestore
            .collection('employees')
            .doc(employeeId)
            .collection('attendance')
            .doc(today)
            .get();

        if (doc.exists) {
          Map<String, dynamic> data = doc.data()!;

          // Convert Timestamp to ISO string
          if (data['checkIn'] != null && data['checkIn'] is Timestamp) {
            data['checkIn'] = (data['checkIn'] as Timestamp).toDate().toIso8601String();
          }
          if (data['checkOut'] != null && data['checkOut'] is Timestamp) {
            data['checkOut'] = (data['checkOut'] as Timestamp).toDate().toIso8601String();
          }

          // Create and save local record
          LocalAttendanceRecord record = LocalAttendanceRecord(
            employeeId: employeeId,
            date: today,
            checkIn: data['checkIn'],
            checkOut: data['checkOut'],
            locationId: data['locationId'],
            isSynced: true,
            rawData: data,
          );

          // Save to local database for future offline use
          await _dbHelper.insert('attendance', record.toMap());

          return record;
        }
      }

      // No record found
      return null;
    } catch (e) {
      print('Error getting today\'s attendance: $e');
      return null;
    }
  }

  // Get recent attendance records
  Future<List<LocalAttendanceRecord>> getRecentAttendance(String employeeId, int limit) async {
    try {
      List<LocalAttendanceRecord> records = [];

      // First try local database
      List<Map<String, dynamic>> localRecords = await _dbHelper.query(
        'attendance',
        where: 'employee_id = ?',
        whereArgs: [employeeId],
        orderBy: 'date DESC',
        limit: limit,
      );

      if (localRecords.isNotEmpty) {
        records = localRecords.map((record) => LocalAttendanceRecord.fromMap(record)).toList();
      }

      // If online and we need more records, check Firestore
      if (_connectivityService.currentStatus == ConnectionStatus.online && records.length < limit) {
        final snapshot = await _firestore
            .collection('employees')
            .doc(employeeId)
            .collection('attendance')
            .orderBy('date', descending: true)
            .limit(limit)
            .get();

        if (snapshot.docs.isNotEmpty) {
          // Process Firestore records
          List<LocalAttendanceRecord> firestoreRecords = [];

          for (var doc in snapshot.docs) {
            Map<String, dynamic> data = doc.data();

            // Convert Timestamps to ISO strings
            if (data['checkIn'] != null && data['checkIn'] is Timestamp) {
              data['checkIn'] = (data['checkIn'] as Timestamp).toDate().toIso8601String();
            }
            if (data['checkOut'] != null && data['checkOut'] is Timestamp) {
              data['checkOut'] = (data['checkOut'] as Timestamp).toDate().toIso8601String();
            }

            LocalAttendanceRecord record = LocalAttendanceRecord(
              employeeId: employeeId,
              date: data['date'],
              checkIn: data['checkIn'],
              checkOut: data['checkOut'],
              locationId: data['locationId'],
              isSynced: true,
              rawData: data,
            );

            firestoreRecords.add(record);

            // Save to local database for future offline use
            await _dbHelper.insert('attendance', record.toMap());
          }

          // Merge and limit records
          records = [...firestoreRecords];
          if (records.length > limit) {
            records = records.sublist(0, limit);
          }
        }
      }

      return records;
    } catch (e) {
      print('Error getting recent attendance: $e');
      return [];
    }
  }

  // Get pending records that need to be synced
  Future<List<LocalAttendanceRecord>> getPendingRecords() async {
    try {
      List<Map<String, dynamic>> maps = await _dbHelper.query(
        'attendance',
        where: 'is_synced = ?',
        whereArgs: [0],
      );

      return maps.map((map) => LocalAttendanceRecord.fromMap(map)).toList();
    } catch (e) {
      print('Error getting pending records: $e');
      return [];
    }
  }

  // Sync pending records with Firestore
  Future<bool> syncPendingRecords() async {
    if (_connectivityService.currentStatus == ConnectionStatus.offline) {
      print("AttendanceRepository: Cannot sync while offline");
      return false;
    }

    try {
      // Get all pending records
      List<LocalAttendanceRecord> pendingRecords = await getPendingRecords();
      print("AttendanceRepository: Syncing ${pendingRecords.length} pending records");

      int successCount = 0;
      int failureCount = 0;

      for (var record in pendingRecords) {
        try {
          print("AttendanceRepository: Syncing record ${record.id} for date ${record.date}");

          // Prepare Firestore data
          Map<String, dynamic> firestoreData = Map<String, dynamic>.from(record.rawData);

          // Convert ISO string dates to Timestamps for Firestore
          if (firestoreData['checkIn'] != null) {
            firestoreData['checkIn'] = Timestamp.fromDate(
                DateTime.parse(firestoreData['checkIn'])
            );
          }
          if (firestoreData['checkOut'] != null) {
            firestoreData['checkOut'] = Timestamp.fromDate(
                DateTime.parse(firestoreData['checkOut'])
            );
          }

          // Update Firestore
          await _firestore
              .collection('employees')
              .doc(record.employeeId)
              .collection('attendance')
              .doc(record.date)
              .set(firestoreData, SetOptions(merge: true));

          // Mark as synced
          await _dbHelper.update(
            'attendance',
            {'is_synced': 1, 'sync_error': null},
            where: 'id = ?',
            whereArgs: [record.id],
          );

          successCount++;
          print("AttendanceRepository: Successfully synced record ${record.id}");
        } catch (e) {
          failureCount++;
          // Update with sync error
          await _dbHelper.update(
            'attendance',
            {'sync_error': e.toString()},
            where: 'id = ?',
            whereArgs: [record.id],
          );
          print('AttendanceRepository: Error syncing record ${record.id}: $e');
        }
      }

      print("AttendanceRepository: Sync completed. Success: $successCount, Failures: $failureCount");
      return failureCount == 0;
    } catch (e) {
      print('AttendanceRepository: Error in syncPendingRecords: $e');
      return false;
    }
  }

  // Get locally stored locations - used for testing
  Future<List<Map<String, dynamic>>> getLocalStoredLocations() async {
    try {
      return await _dbHelper.query('locations');
    } catch (e) {
      print('Error getting local locations: $e');
      return [];
    }
  }
}