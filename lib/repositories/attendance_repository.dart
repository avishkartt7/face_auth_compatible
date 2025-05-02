// lib/repositories/attendance_repository.dart

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
      // Format today's date as YYYY-MM-DD for the document ID
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Prepare data for both online and offline storage
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
        rawData: checkInData,
      );

      // If online, try to save to Firestore first
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        await _firestore
            .collection('employees')
            .doc(employeeId)
            .collection('attendance')
            .doc(today)
            .set(checkInData, SetOptions(merge: true));

        // Mark as synced in local storage
        localRecord = LocalAttendanceRecord(
          employeeId: employeeId,
          date: today,
          checkIn: checkInTime.toIso8601String(),
          locationId: locationId,
          isSynced: true,
          rawData: checkInData,
        );
      }

      // Always save to local database regardless of online status
      await _dbHelper.insert('attendance', localRecord.toMap());

      return true;
    } catch (e) {
      print('Error recording check-in: $e');
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

      // First, check if we have a local record
      List<Map<String, dynamic>> localRecords = await _dbHelper.query(
        'attendance',
        where: 'employee_id = ? AND date = ?',
        whereArgs: [employeeId, today],
      );

      if (localRecords.isEmpty) {
        return false; // No check-in record found
      }

      // Get the local record and update it
      LocalAttendanceRecord record = LocalAttendanceRecord.fromMap(localRecords.first);
      DateTime checkInTime = DateTime.parse(record.checkIn!);

      // Calculate working hours
      double hoursWorked = checkOutTime.difference(checkInTime).inMinutes / 60;

      // Update the raw data
      Map<String, dynamic> updatedData = Map<String, dynamic>.from(record.rawData);
      updatedData['checkOut'] = checkOutTime.toIso8601String();
      updatedData['workStatus'] = 'Completed';
      updatedData['totalHours'] = hoursWorked;

      // Prepare the updated local record
      LocalAttendanceRecord updatedRecord = LocalAttendanceRecord(
        id: record.id,
        employeeId: employeeId,
        date: today,
        checkIn: record.checkIn,
        checkOut: checkOutTime.toIso8601String(),
        locationId: record.locationId,
        isSynced: _connectivityService.currentStatus == ConnectionStatus.online,
        rawData: updatedData,
      );

      // If online, update Firestore
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        await _firestore
            .collection('employees')
            .doc(employeeId)
            .collection('attendance')
            .doc(today)
            .update({
          'checkOut': checkOutTime.toIso8601String(),
          'workStatus': 'Completed',
          'totalHours': hoursWorked,
        });
      }

      // Update local record
      await _dbHelper.update(
        'attendance',
        updatedRecord.toMap(),
        where: 'id = ?',
        whereArgs: [record.id],
      );

      return true;
    } catch (e) {
      print('Error recording check-out: $e');
      return false;
    }
  }

  // Get today's attendance record
  Future<LocalAttendanceRecord?> getTodaysAttendance(String employeeId) async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      // First check local database
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
      return false; // Can't sync while offline
    }

    try {
      // Get all pending records
      List<LocalAttendanceRecord> pendingRecords = await getPendingRecords();

      for (var record in pendingRecords) {
        try {
          await _firestore
              .collection('employees')
              .doc(record.employeeId)
              .collection('attendance')
              .doc(record.date)
              .set(record.rawData, SetOptions(merge: true));

          // Mark as synced
          await _dbHelper.update(
            'attendance',
            {'is_synced': 1, 'sync_error': null},
            where: 'id = ?',
            whereArgs: [record.id],
          );
        } catch (e) {
          // Update with sync error
          await _dbHelper.update(
            'attendance',
            {'sync_error': e.toString()},
            where: 'id = ?',
            whereArgs: [record.id],
          );
          print('Error syncing record ${record.id}: $e');
        }
      }

      return true;
    } catch (e) {
      print('Error syncing records: $e');
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