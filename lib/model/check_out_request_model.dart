// lib/model/check_out_request_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum CheckOutRequestStatus {
  pending,
  approved,
  rejected
}

class CheckOutRequest {
  final String id;
  final String employeeId;
  final String employeeName;
  final String lineManagerId;
  final DateTime requestTime;
  final double latitude;
  final double longitude;
  final String locationName;
  final String reason;
  final CheckOutRequestStatus status;
  final DateTime? responseTime;
  final String? responseMessage;
  final String requestType; // Added 'check-in' or 'check-out'

  CheckOutRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.lineManagerId,
    required this.requestTime,
    required this.latitude,
    required this.longitude,
    required this.locationName,
    required this.reason,
    required this.status,
    this.responseTime,
    this.responseMessage,
    required this.requestType, // Default to check-out for backward compatibility
  });

  factory CheckOutRequest.fromMap(Map<String, dynamic> map, String id) {
    return CheckOutRequest(
      id: id,
      employeeId: map['employeeId'] ?? '',
      employeeName: map['employeeName'] ?? '',
      lineManagerId: map['lineManagerId'] ?? '',
      requestTime: (map['requestTime'] as Timestamp).toDate(),
      latitude: map['latitude'] ?? 0.0,
      longitude: map['longitude'] ?? 0.0,
      locationName: map['locationName'] ?? 'Unknown Location',
      reason: map['reason'] ?? '',
      status: CheckOutRequestStatus.values.firstWhere(
              (e) => e.toString() == 'CheckOutRequestStatus.${map['status']}',
          orElse: () => CheckOutRequestStatus.pending
      ),
      responseTime: map['responseTime'] != null
          ? (map['responseTime'] as Timestamp).toDate()
          : null,
      responseMessage: map['responseMessage'],
      requestType: map['requestType'] ?? 'check-out', // Default for backward compatibility
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'employeeId': employeeId,
      'employeeName': employeeName,
      'lineManagerId': lineManagerId,
      'requestTime': Timestamp.fromDate(requestTime),
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'reason': reason,
      'status': status.toString().split('.').last,
      'responseTime': responseTime != null ? Timestamp.fromDate(responseTime!) : null,
      'responseMessage': responseMessage,
      'requestType': requestType,
    };
  }

  // Create a new request
  static CheckOutRequest createNew({
    required String employeeId,
    required String employeeName,
    required String lineManagerId,
    required double latitude,
    required double longitude,
    required String locationName,
    required String reason,
    required String requestType, // Added parameter
  }) {
    return CheckOutRequest(
      id: '', // Will be set by Firestore
      employeeId: employeeId,
      employeeName: employeeName,
      lineManagerId: lineManagerId,
      requestTime: DateTime.now(),
      latitude: latitude,
      longitude: longitude,
      locationName: locationName,
      reason: reason,
      status: CheckOutRequestStatus.pending,
      requestType: requestType,
    );
  }

  // Create a copy with updated status
  CheckOutRequest withResponse({
    required CheckOutRequestStatus status,
    String? responseMessage,
  }) {
    return CheckOutRequest(
      id: this.id,
      employeeId: this.employeeId,
      employeeName: this.employeeName,
      lineManagerId: this.lineManagerId,
      requestTime: this.requestTime,
      latitude: this.latitude,
      longitude: this.longitude,
      locationName: this.locationName,
      reason: this.reason,
      status: status,
      responseTime: DateTime.now(),
      responseMessage: responseMessage ?? this.responseMessage,
      requestType: this.requestType,
    );
  }
}

