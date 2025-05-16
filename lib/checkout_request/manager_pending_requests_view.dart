// lib/checkout_request/manager_pending_requests_view.dart

import 'package:flutter/material.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/model/check_out_request_model.dart';
import 'package:face_auth_compatible/repositories/check_out_request_repository.dart';
import 'package:face_auth_compatible/services/service_locator.dart';
import 'package:face_auth_compatible/services/notification_service.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ManagerPendingRequestsView extends StatefulWidget {
  final String managerId;

  const ManagerPendingRequestsView({
    Key? key,
    required this.managerId,
  }) : super(key: key);

  @override
  State<ManagerPendingRequestsView> createState() => _ManagerPendingRequestsViewState();
}

class _ManagerPendingRequestsViewState extends State<ManagerPendingRequestsView> {
  bool _isLoading = true;
  List<CheckOutRequest> _pendingRequests = [];

  @override
  void initState() {
    super.initState();
    _loadPendingRequests();

    // Subscribe to notifications for this manager
    final notificationService = getIt<NotificationService>();
    notificationService.subscribeToManagerTopic('manager_${widget.managerId}');
  }

  @override
  void dispose() {
    // It's good practice to unsubscribe when not needed anymore
    final notificationService = getIt<NotificationService>();
    notificationService.unsubscribeFromManagerTopic('manager_${widget.managerId}');
    super.dispose();
  }

  Future<void> _loadPendingRequests() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final repository = getIt<CheckOutRequestRepository>();
      final requests = await repository.getPendingRequestsForManager(widget.managerId);

      setState(() {
        _pendingRequests = requests;
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading pending requests: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _respondToRequest(CheckOutRequest request, bool isApproved, String? message) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final repository = getIt<CheckOutRequestRepository>();

      // Update the request status
      final status = isApproved ? CheckOutRequestStatus.approved : CheckOutRequestStatus.rejected;
      bool success = await repository.respondToRequest(request.id, status, message);

      if (success) {
        // Send notification to employee
        await _notifyEmployee(request.employeeId, isApproved, message);

        // Refresh the pending requests list
        await _loadPendingRequests();

        CustomSnackBar.successSnackBar(
            isApproved ? "Request approved successfully" : "Request rejected"
        );
      } else {
        CustomSnackBar.errorSnackBar("Failed to update request");
      }
    } catch (e) {
      CustomSnackBar.errorSnackBar("Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _notifyEmployee(String employeeId, bool isApproved, String? message) async {
    try {
      // Get employee's FCM token from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('fcm_tokens')
          .doc(employeeId)
          .get();

      if (!doc.exists) {
        print("No FCM token found for employee $employeeId");
        return;
      }

      String? token = doc.data()?['token'];
      if (token == null) {
        print("FCM token is null for employee $employeeId");
        return;
      }

      // Send notification via Firebase Cloud Function
      await FirebaseFirestore.instance.collection('notifications').add({
        'token': token,
        'title': isApproved ? 'Check-Out Request Approved' : 'Check-Out Request Rejected',
        'body': isApproved
            ? 'Your request to check out has been approved'
            : 'Your request to check out has been rejected',
        'data': {
          'type': 'check_out_request_response',
          'employeeId': employeeId,
          'approved': isApproved,
          'message': message ?? '',
        },
        'sentAt': FieldValue.serverTimestamp(),
      });

      print("Notification scheduled for employee $employeeId");
    } catch (e) {
      print("Error sending notification: $e");
    }
  }

  void _showResponseDialog(CheckOutRequest request, bool isApproving) {
    final TextEditingController messageController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isApproving ? "Approve Request" : "Reject Request"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isApproving
                  ? "Are you sure you want to approve this check-out request?"
                  : "Are you sure you want to reject this check-out request?",
            ),
            const SizedBox(height: 16),
            TextField(
              controller: messageController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: isApproving ? "Optional comment" : "Reason for rejection",
                hintText: isApproving
                    ? "Add any additional instructions..."
                    : "Please provide a reason...",
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _respondToRequest(
                  request,
                  isApproving,
                  messageController.text.trim().isEmpty ? null : messageController.text.trim()
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isApproving ? accentColor : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(isApproving ? "Approve" : "Reject"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pending Approval Requests"),
        backgroundColor: scaffoldTopGradientClr,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingRequests,
            tooltip: "Refresh",
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scaffoldTopGradientClr,
              scaffoldBottomGradientClr,
            ],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: accentColor))
            : _pendingRequests.isEmpty
            ? _buildEmptyState()
            : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _pendingRequests.length,
          itemBuilder: (context, index) {
            return _buildRequestCard(_pendingRequests[index]);
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 64,
            color: Colors.white.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            "No pending requests",
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "When employees request to check out from outside the office, their requests will appear here",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(CheckOutRequest request) {
    final dateFormat = DateFormat('EEE, MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Employee name and time
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    request.employeeName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    timeFormat.format(request.requestTime),
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),

            Text(
              dateFormat.format(request.requestTime),
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),

            // Location
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Location",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        request.locationName,
                        style: const TextStyle(
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Reason
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.subject, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Reason",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        request.reason,
                        style: const TextStyle(
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showResponseDialog(request, false),
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    label: const Text("Reject"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showResponseDialog(request, true),
                    icon: const Icon(Icons.check_circle),
                    label: const Text("Approve"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}