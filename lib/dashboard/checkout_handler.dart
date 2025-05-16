// lib/dashboard/checkout_handler.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:face_auth_compatible/checkout_request/create_request_view.dart';
import 'package:face_auth_compatible/checkout_request/request_history_view.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/repositories/check_out_request_repository.dart';
import 'package:face_auth_compatible/model/check_out_request_model.dart';
import 'package:face_auth_compatible/services/service_locator.dart';

class CheckoutHandler {
  // Method to handle check-out process
  static Future<bool> handleCheckOut({
    required BuildContext context,
    required String employeeId,
    required String employeeName,
    required bool isWithinGeofence,
    required Position? currentPosition,
    required VoidCallback onRegularCheckOut,
  }) async {
    // If within geofence, proceed with normal check-out
    if (isWithinGeofence) {
      onRegularCheckOut();
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
        req.requestTime.day == today.day
    ).toList();

    if (approvedRequests.isNotEmpty) {
      // There's already an approved request, proceed with check-out
      onRegularCheckOut();
      return true;
    }

    // Check for pending requests today
    final pendingRequests = requests.where((req) =>
    req.status == CheckOutRequestStatus.pending &&
        req.requestTime.year == today.year &&
        req.requestTime.month == today.month &&
        req.requestTime.day == today.day
    ).toList();

    if (pendingRequests.isNotEmpty) {
      // Already has a pending request, show it
      return await _showPendingRequestOptions(context, employeeId);
    }

    // No approved or pending requests yet, show the request form
    return await _showCreateRequestForm(
      context,
      employeeId,
      employeeName,
      currentPosition,
    );
  }

  // Show pending request options
  static Future<bool> _showPendingRequestOptions(
      BuildContext context,
      String employeeId
      ) async {
    bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Pending Check-Out Request"),
        content: const Text(
            "You already have a pending request to check out from your current location. "
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
      ) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCheckOutRequestView(
          employeeId: employeeId,
          employeeName: employeeName,
          currentPosition: currentPosition,
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