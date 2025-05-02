// lib/model/local_attendance_model.dart

import 'dart:convert';

class LocalAttendanceRecord {
  final int? id; // Local database ID
  final String employeeId;
  final String date;
  final String? checkIn;
  final String? checkOut;
  final String? locationId;
  final bool isSynced;
  final String? syncError;
  final Map<String, dynamic> rawData;

  LocalAttendanceRecord({
    this.id,
    required this.employeeId,
    required this.date,
    this.checkIn,
    this.checkOut,
    this.locationId,
    this.isSynced = false,
    this.syncError,
    required this.rawData,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employee_id': employeeId,
      'date': date,
      'check_in': checkIn,
      'check_out': checkOut,
      'location_id': locationId,
      'is_synced': isSynced ? 1 : 0,
      'sync_error': syncError,
      'raw_data': jsonEncode(rawData),
    };
  }

  factory LocalAttendanceRecord.fromMap(Map<String, dynamic> map) {
    return LocalAttendanceRecord(
      id: map['id'],
      employeeId: map['employee_id'],
      date: map['date'],
      checkIn: map['check_in'],
      checkOut: map['check_out'],
      locationId: map['location_id'],
      isSynced: map['is_synced'] == 1,
      syncError: map['sync_error'],
      rawData: jsonDecode(map['raw_data']),
    );
  }
}