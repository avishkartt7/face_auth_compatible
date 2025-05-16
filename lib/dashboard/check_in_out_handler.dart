// lib/dashboard/check_in_out_handler.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:face_auth_compatible/checkout_request/create_request_view.dart';
import 'package:face_auth_compatible/checkout_request/request_history_view.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/repositories/check_out_request_repository.dart';
import 'package:face_auth_compatible/model/check_out_request_model.dart';
import 'package:face_auth_compatible/services/service_locator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CheckInOutHandler {
  // Method to handle check-in/check-out process when outside geofence
  static Future<bool> handleOffLocationAction({
    required BuildContext context,
    required String employeeId,
    required String employeeName,
    required bool isWithinGeofence,
    required Position? currentPosition,
    required VoidCallback onRegularAction,
    required bool isCheckIn, // New parameter to distinguish between check-in and check-out
  }) async {
    // If within geofence, proceed with normal action
    if (isWithinGeofence) {
      onRegularAction();
      return true;
    }

    // If not within geofence, we need to handle it differently
    if (currentPosition == null) {
      CustomSnackBar.errorSnackBar("Unable to get your current location. Please try again.");
      return false;
    }

    // Check if there's an approved request for today
    final repository = getIt<CheckOutRequestRepository>();
    final requests = await repository.getRequestsForEmployee(employeeId);

    // Filter for today's approved requests
    final today = DateTime.now();
    final approvedRequests = requests.where((req) =>
    req.status == CheckOutRequestStatus.approved &&
        req.requestTime.year == today.year &&
        req.requestTime.month == today.month &&
        req.requestTime.day == today.day &&
        req.requestType == (isCheckIn ? 'check-in' : 'check-out')
    ).toList();

    if (approvedRequests.isNotEmpty) {
      // There's already an approved request, proceed with regular action
      onRegularAction();
      return true;
    }

    // Check for pending requests today for this action type
    final pendingRequests = requests.where((req) =>
    req.status == CheckOutRequestStatus.pending &&
        req.requestTime.year == today.year &&
        req.requestTime.month == today.month &&
        req.requestTime.day == today.day &&
        req.requestType == (isCheckIn ? 'check-in' : 'check-out')
    ).toList();

    if (pendingRequests.isNotEmpty) {
      // Already has a pending request, show it
      return await _showPendingRequestOptions(context, employeeId, isCheckIn);
    }

    // No approved or pending requests yet, get the manager ID and show the request form
    String? lineManagerId = await _getLineManagerId(employeeId);

    // Show request form (the lineManagerId will be found in the form if null here)
    return await _showCreateRequestForm(
      context,
      employeeId,
      employeeName,
      currentPosition,
      lineManagerId,
      isCheckIn,
    );
  }

  // Find line manager for the employee
  static Future<String?> _getLineManagerId(String employeeId) async {
    try {
      // First check cached manager info
      final prefs = await SharedPreferences.getInstance();
      String? cachedManagerId = prefs.getString('line_manager_id_$employeeId');

      if (cachedManagerId != null) {
        print("Found cached manager ID: $cachedManagerId");
        return cachedManagerId;
      }

      // If no cached value, try to get from Firestore
      // First check employee's own document for lineManagerId field
      final employeeDoc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .get();

      if (employeeDoc.exists) {
        Map<String, dynamic> data = employeeDoc.data() as Map<String, dynamic>;

        if (data.containsKey('lineManagerId') && data['lineManagerId'] != null) {
          String managerId = data['lineManagerId'];

          // Cache for next time
          await prefs.setString('line_manager_id_$employeeId', managerId);

          print("Found manager ID in employee doc: $managerId");
          return managerId;
        }
      }

      // If not found in employee doc, check line_managers collection
      print("Checking line_managers collection for employee: $employeeId");

      // Try different formats that might be used in the database
      final List<String> possibleEmployeeIds = [
        employeeId,
        'EMP$employeeId',
        employeeId.startsWith('EMP') ? employeeId.substring(3) : employeeId,
      ];

      for (String empId in possibleEmployeeIds) {
        print("Checking for team member: $empId");
        final lineManagerQuery = await FirebaseFirestore.instance
            .collection('line_managers')
            .where('teamMembers', arrayContains: empId)
            .limit(1)
            .get();

        if (lineManagerQuery.docs.isNotEmpty) {
          final managerDoc = lineManagerQuery.docs.first;
          final managerId = managerDoc.data()['managerId'];

          // Cache for next time
          await prefs.setString('line_manager_id_$employeeId', managerId);

          print("Found manager ID in line_managers collection: $managerId");
          return managerId;
        }
      }

      print("No manager found for employee: $employeeId");
      return null;
    } catch (e) {
      print("Error looking up manager: $e");
      return null;
    }
  }

  // Show pending request options
  static Future<bool> _showPendingRequestOptions(
      BuildContext context,
      String employeeId,
      bool isCheckIn
      ) async {
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Pending ${isCheckIn ? 'Check-In' : 'Check-Out'} Request"),
        content: Text(
            "You already have a pending request to ${isCheckIn ? 'check in' : 'check out'} from your current location. "
                "Do you want to view the status of your request or create a new one?"
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              // Show request history
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CheckOutRequestHistoryView(
                    employeeId: employeeId,
                  ),
                ),
              );

              // If returned with an approved request
              if (result != null && result is Map && result['approved'] == true) {
                Navigator.pop(context, true);
              }
            },
            child: const Text("View Requests"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Create New Request"),
          ),
        ],
      ),
    );

    if (result == true) {
      // User wants to create a new request
      return false;
    }

    return false;
  }

  // Show create request form
  static Future<bool> _showCreateRequestForm(
      BuildContext context,
      String employeeId,
      String employeeName,
      Position currentPosition,
      String? lineManagerId,
      bool isCheckIn,
      ) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCheckOutRequestView(
          employeeId: employeeId,
          employeeName: employeeName,
          currentPosition: currentPosition,
          extra: {
            'lineManagerId': lineManagerId,
            'isCheckIn': isCheckIn,
          },
        ),
      ),
    );

    // Return true if the request was submitted successfully
    return result ?? false;
  }

  // Show request history
  static Future<void> showRequestHistory(
      BuildContext context,
      String employeeId,
      ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CheckOutRequestHistoryView(
          employeeId: employeeId,
        ),
      ),
    );
  }
}