// lib/dashboard/check_in_out_handler.dart - Updated version

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
    required bool isCheckIn, // This parameter indicates whether this is check-in or check-out
  }) async {
    // If within geofence, proceed with normal action
    if (isWithinGeofence) {
      onRegularAction();
      return true;
    }

    debugPrint("CheckInOutHandler: Outside geofence, handling as ${isCheckIn ? 'check-in' : 'check-out'} request");

    // If not within geofence, we need to handle it differently
    if (currentPosition == null) {
      CustomSnackBar.errorSnackBar("Unable to get your current location. Please try again.");
      return false;
    }

    // Check if there's an approved request for today - making sure to filter by request type
    final repository = getIt<CheckOutRequestRepository>();
    final requests = await repository.getRequestsForEmployee(employeeId);

    debugPrint("CheckInOutHandler: Found ${requests.length} requests for employee $employeeId");
    for (var req in requests) {
      debugPrint("Request: ID=${req.id}, Type=${req.requestType}, Status=${req.status}");
    }

    // Filter for today's approved requests of the specific type (check-in or check-out)
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
      debugPrint("Found approved ${isCheckIn ? 'check-in' : 'check-out'} request - proceeding with regular action");
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

    debugPrint("CheckInOutHandler: Found ${pendingRequests.length} pending ${isCheckIn ? 'check-in' : 'check-out'} requests for today");

    if (pendingRequests.isNotEmpty) {
      // Already has a pending request, show it
      debugPrint("Found pending ${isCheckIn ? 'check-in' : 'check-out'} request - showing options");
      final shouldCreateNew = await _showPendingRequestOptions(context, employeeId, isCheckIn);

      if (shouldCreateNew) {
        debugPrint("User chose to create a new request despite having a pending one");
        // Get the manager ID and show the request form
        String? lineManagerId = await _getLineManagerId(employeeId);

        debugPrint("Line manager ID for request: $lineManagerId");

        // Show request form
        return await _showCreateRequestForm(
          context,
          employeeId,
          employeeName,
          currentPosition,
          lineManagerId,
          isCheckIn,
        );
      }

      return false;
    }

    // No approved or pending requests yet, get the manager ID and show the request form
    String? lineManagerId = await _getLineManagerId(employeeId);

    debugPrint("Line manager ID for request: $lineManagerId");

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
      debugPrint("Searching for line manager of employee: $employeeId");
      // First check cached manager info
      final prefs = await SharedPreferences.getInstance();
      String? cachedManagerId = prefs.getString('line_manager_id_$employeeId');

      if (cachedManagerId != null) {
        debugPrint("Found cached manager ID: $cachedManagerId");
        return cachedManagerId;
      }

      // If no cached value, try multiple search approaches:

      // 1. First check the employee's own document for lineManagerId field
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
          debugPrint("Found manager ID in employee doc: $managerId");
          return managerId;
        }
      }

      // 2. If not found in employee doc, check line_managers collection with multiple ID formats
      debugPrint("Checking line_managers collection for employee: $employeeId");

      // Get employee's PIN for additional search
      String employeePin = '';
      if (employeeDoc.exists) {
        Map<String, dynamic> data = employeeDoc.data() as Map<String, dynamic>;
        employeePin = data['pin'] ?? '';
      }

      // Try different formats that might be used in the database
      final List<String> possibleEmployeeIds = [
        employeeId,
        employeeId.replaceFirst('EMP', ''), // Remove EMP prefix if present
        'EMP$employeeId', // Add EMP prefix if not present
        employeePin,
      ];

      // Debug info
      debugPrint("Checking for employee with possible IDs: $possibleEmployeeIds");

      final lineManagersSnapshot = await FirebaseFirestore.instance
          .collection('line_managers')
          .get();

      debugPrint("Found ${lineManagersSnapshot.docs.length} line manager documents");

      // Iterate through all line manager documents
      for (var doc in lineManagersSnapshot.docs) {
        Map<String, dynamic> data = doc.data();
        List<dynamic> teamMembers = data['teamMembers'] ?? [];

        debugPrint("Checking line manager doc ${doc.id} with ${teamMembers.length} team members");
        debugPrint("Team members: $teamMembers");

        // Check if any of the possible IDs are in the team members array
        for (String empId in possibleEmployeeIds) {
          if (teamMembers.contains(empId)) {
            String managerId = data['managerId'];
            debugPrint("Found! Employee is in team of manager: $managerId");

            // Cache for next time
            await prefs.setString('line_manager_id_$employeeId', managerId);
            return managerId;
          }
        }
      }

      // If still not found, try to find any manager
      debugPrint("No specific manager found - searching for any manager");
      final managerQuery = await FirebaseFirestore.instance
          .collection('employees')
          .where('isManager', isEqualTo: true)
          .limit(1)
          .get();

      if (managerQuery.docs.isNotEmpty) {
        String fallbackManagerId = managerQuery.docs[0].id;
        debugPrint("Using fallback manager ID: $fallbackManagerId");

        // Cache for next time
        await prefs.setString('line_manager_id_$employeeId', fallbackManagerId);

        return fallbackManagerId;
      }

      // Default to a hardcoded ID if necessary (should be set based on your specific database)
      debugPrint("Using hardcoded default manager: EMP1270");
      return "EMP1270";
    } catch (e) {
      debugPrint("Error looking up manager: $e");
      // Return a default manager ID if all else fails
      return "EMP1270";
    }
  }

  // Show pending request options
  static Future<bool> _showPendingRequestOptions(
      BuildContext context,
      String employeeId,
      bool isCheckIn
      ) async {
    debugPrint("HANDLER: Showing pending request options dialog");

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
            onPressed: () {
              debugPrint("HANDLER: Dialog - Cancel button pressed");
              Navigator.pop(context, false);
            },
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              debugPrint("HANDLER: Dialog - View Requests button pressed");
              Navigator.pop(context, false); // First pop the dialog with 'false' result

              // Show request history
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CheckOutRequestHistoryView(
                    employeeId: employeeId,
                  ),
                ),
              );

              debugPrint("HANDLER: Returned from request history with result: $result");
              // Don't return anything here - this is a void function
            },
            child: const Text("View Requests"),
          ),
          TextButton(
            onPressed: () {
              debugPrint("HANDLER: Dialog - Create New Request button pressed");
              Navigator.pop(context, true);
            },
            child: const Text("Create New Request"),
          ),
        ],
      ),
    );

    debugPrint("HANDLER: Dialog result: $result");

    // Fixed: Return true to indicate we should proceed with creating a new request
    return result == true;
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
    debugPrint("Creating ${isCheckIn ? 'check-in' : 'check-out'} request form for $employeeId");
    debugPrint("Line manager ID being passed: $lineManagerId");

    // Log the request details for debugging
    debugPrint("Create Request Details:");
    debugPrint("- Employee ID: $employeeId");
    debugPrint("- Employee Name: $employeeName");
    debugPrint("- Manager ID: $lineManagerId");
    debugPrint("- Request Type: ${isCheckIn ? 'check-in' : 'check-out'}");
    debugPrint("- Position: ${currentPosition.latitude}, ${currentPosition.longitude}");

    try {
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

      debugPrint("Request form returned with result: $result");

      // Return true if the request was submitted successfully
      return result ?? false;
    } catch (e) {
      debugPrint("Error showing create request form: $e");
      return false;
    }
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

  // Debug function to directly create a test check-out request
  static Future<bool> createTestRequest(
      String employeeId,
      String employeeName,
      String lineManagerId,
      Position currentPosition,
      bool isCheckIn
      ) async {
    try {
      debugPrint("Creating TEST ${isCheckIn ? 'check-in' : 'check-out'} request");

      final repository = getIt<CheckOutRequestRepository>();

      // Create request object
      CheckOutRequest request = CheckOutRequest.createNew(
        employeeId: employeeId,
        employeeName: employeeName,
        lineManagerId: lineManagerId,
        latitude: currentPosition.latitude,
        longitude: currentPosition.longitude,
        locationName: "Test Location (${currentPosition.latitude}, ${currentPosition.longitude})",
        reason: "This is a test request created for debugging",
        requestType: isCheckIn ? 'check-in' : 'check-out',
      );

      // Save directly to Firestore for debugging
      try {
        DocumentReference docRef = await FirebaseFirestore.instance
            .collection('check_out_requests')
            .add(request.toMap());

        debugPrint("Test request created successfully in Firestore: ${docRef.id}");

        // Also try the repository method
        bool repoSuccess = await repository.createCheckOutRequest(request);
        debugPrint("Repository save result: $repoSuccess");

        return true;
      } catch (e) {
        debugPrint("Error saving test request to Firestore: $e");

        // Try repository as fallback
        return await repository.createCheckOutRequest(request);
      }
    } catch (e) {
      debugPrint("Error creating test request: $e");
      return false;
    }
  }
}