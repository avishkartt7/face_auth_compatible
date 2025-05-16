import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/model/check_out_request_model.dart';
import 'package:face_auth_compatible/repositories/check_out_request_repository.dart';
import 'package:face_auth_compatible/services/service_locator.dart';
import 'package:face_auth_compatible/services/notification_service.dart';
import 'package:intl/intl.dart';

class ManagerPendingRequestsView extends StatefulWidget {
  final String managerId;

  const ManagerPendingRequestsView({
    Key? key,
    required this.managerId,
  }) : super(key: key);

  @override
  State<ManagerPendingRequestsView> createState() => _ManagerPendingRequestsViewState();
}

class _ManagerPendingRequestsViewState extends State<ManagerPendingRequestsView> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<CheckOutRequest> _pendingRequests = [];
  late TabController _tabController;
  String _filterType = 'all'; // 'all', 'check-in', or 'check-out'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);
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
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;

    setState(() {
      switch (_tabController.index) {
        case 0:
          _filterType = 'all';
          break;
        case 1:
          _filterType = 'check-in';
          break;
        case 2:
          _filterType = 'check-out';
          break;
      }
    });
  }

  Future<void> _loadPendingRequests() async {
    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint("MANAGER VIEW: Starting to load pending requests");
      debugPrint("MANAGER VIEW: Manager ID: ${widget.managerId}");

      // Prepare different formats to check for manager ID
      List<String> possibleManagerIds = [
        widget.managerId,
        widget.managerId.startsWith('EMP') ? widget.managerId.substring(3) : 'EMP${widget.managerId}',
      ];

      debugPrint("MANAGER VIEW: Checking manager IDs: $possibleManagerIds");

      List<CheckOutRequest> allRequests = [];
      final repository = getIt<CheckOutRequestRepository>();

      // Try multiple formats for direct Firestore query first
      for (String managerId in possibleManagerIds) {
        debugPrint("MANAGER VIEW: Trying direct Firestore query for manager ID: $managerId");

        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('check_out_requests')
              .where('lineManagerId', isEqualTo: managerId)
              .where('status', isEqualTo: 'pending')
              .get();

          debugPrint("MANAGER VIEW: Direct query found ${snapshot.docs.length} requests for $managerId");

          for (var doc in snapshot.docs) {
            try {
              CheckOutRequest request = CheckOutRequest.fromMap(doc.data(), doc.id);
              allRequests.add(request);
              debugPrint("MANAGER VIEW: Added request ${doc.id} from direct query");
            } catch (e) {
              debugPrint("MANAGER VIEW: Error parsing request from direct query: $e");
            }
          }
        } catch (e) {
          debugPrint("MANAGER VIEW: Error in direct Firestore query for $managerId: $e");
        }
      }

      // Now try repository method for each manager ID format
      for (String managerId in possibleManagerIds) {
        debugPrint("MANAGER VIEW: Trying repository method for manager ID: $managerId");

        try {
          final requests = await repository.getPendingRequestsForManager(managerId);

          if (requests.isNotEmpty) {
            debugPrint("MANAGER VIEW: Repository found ${requests.length} requests for $managerId");
            allRequests.addAll(requests);
          }
        } catch (e) {
          debugPrint("MANAGER VIEW: Error using repository for $managerId: $e");
        }
      }

      // Check all pending requests in the database to make sure we're not missing anything
      try {
        debugPrint("MANAGER VIEW: Checking all pending requests in the database");
        final allPendingRequests = await FirebaseFirestore.instance
            .collection('check_out_requests')
            .where('status', isEqualTo: 'pending')
            .get();

        debugPrint("MANAGER VIEW: Total pending requests in database: ${allPendingRequests.docs.length}");

        // Look for any that might belong to this manager but were missed
        for (var doc in allPendingRequests.docs) {
          String docLineManagerId = doc.data()['lineManagerId'] ?? '';
          bool belongsToThisManager = possibleManagerIds.contains(docLineManagerId);

          if (belongsToThisManager) {
            try {
              CheckOutRequest request = CheckOutRequest.fromMap(doc.data(), doc.id);
              allRequests.add(request);
              debugPrint("MANAGER VIEW: Found additional request ${doc.id} for manager");
            } catch (e) {
              debugPrint("MANAGER VIEW: Error parsing additional request: $e");
            }
          }
        }
      } catch (e) {
        debugPrint("MANAGER VIEW: Error checking all pending requests: $e");
      }

      // Remove duplicates by ID
      final uniqueRequests = <String, CheckOutRequest>{};
      for (var request in allRequests) {
        uniqueRequests[request.id] = request;
      }

      final finalRequests = uniqueRequests.values.toList();
      debugPrint("MANAGER VIEW: Total unique requests found: ${finalRequests.length}");

      setState(() {
        _pendingRequests = finalRequests;
        _isLoading = false;
      });

      // Force UI update if we got results
      if (_pendingRequests.isNotEmpty) {
        Future.delayed(Duration.zero, () {
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      debugPrint("MANAGER VIEW: Error loading pending requests: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Debug method to check manager ID and requests
  Future<void> _debugCheckManagerId() async {
    try {
      debugPrint("=== DEBUG MANAGER ID ===");
      debugPrint("Current Manager ID: ${widget.managerId}");

      // Check all possible formats
      List<String> possibleIds = [
        widget.managerId,
        widget.managerId.startsWith('EMP') ? widget.managerId.substring(3) : 'EMP${widget.managerId}',
      ];

      debugPrint("Checking formats: $possibleIds");

      // Try direct Firestore query to find manager's requests
      for (String format in possibleIds) {
        final snapshot = await FirebaseFirestore.instance
            .collection('check_out_requests')
            .where('lineManagerId', isEqualTo: format)
            .get();

        debugPrint("Format '$format' found ${snapshot.docs.length} requests");

        for (var doc in snapshot.docs) {
          debugPrint("Request ID: ${doc.id}");
          debugPrint("Status: ${doc.data()['status']}");
          debugPrint("Employee: ${doc.data()['employeeName']}");
        }
      }

      // Check specifically for pending requests
      final pendingSnapshot = await FirebaseFirestore.instance
          .collection('check_out_requests')
          .where('status', isEqualTo: 'pending')
          .get();

      debugPrint("Found ${pendingSnapshot.docs.length} total pending requests");

      // Check for specific document if known
      if (pendingSnapshot.docs.isNotEmpty) {
        final requestId = pendingSnapshot.docs.first.id;
        final specificRequest = await FirebaseFirestore.instance
            .collection('check_out_requests')
            .doc(requestId)
            .get();

        if (specificRequest.exists) {
          debugPrint("Found specific request: ${specificRequest.data()}");
        } else {
          debugPrint("Specific request not found!");
        }
      }

      debugPrint("======================");

      CustomSnackBar.successSnackBar("Debug info printed to console. Found ${pendingSnapshot.docs.length} pending requests.");
    } catch (e) {
      debugPrint("Error in debug: $e");
      CustomSnackBar.errorSnackBar("Debug error: $e");
    }
  }

  // Direct Firestore query method - bypass repository
  Future<void> _directFirestoreQuery() async {
    setState(() => _isLoading = true);
    _pendingRequests.clear();

    try {
      // Get ALL pending requests in the database
      final snapshot = await FirebaseFirestore.instance
          .collection('check_out_requests')
          .where('status', isEqualTo: 'pending')
          .get();

      debugPrint("DIRECT: Found ${snapshot.docs.length} total pending requests");

      List<CheckOutRequest> requests = [];

      // Convert to CheckOutRequest objects
      for (var doc in snapshot.docs) {
        try {
          requests.add(CheckOutRequest.fromMap(doc.data(), doc.id));
        } catch (e) {
          debugPrint("Error parsing request ${doc.id}: $e");
        }
      }

      setState(() {
        _pendingRequests = requests;
        _isLoading = false;
      });

      CustomSnackBar.successSnackBar("Found ${_pendingRequests.length} requests via direct query");
    } catch (e) {
      debugPrint("DIRECT: Error: $e");
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar("Direct query error: $e");
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
        await _notifyEmployee(request.employeeId, isApproved, message, request.requestType);

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

  Future<void> _notifyEmployee(String employeeId, bool isApproved, String? message, String requestType) async {
    try {
      // Get employee's FCM token from Firestore
      final doc = await FirebaseFirestore.instance
          .collection('fcm_tokens')
          .doc(employeeId)
          .get();

      if (!doc.exists) {
        // Try alternative format (with/without EMP prefix)
        String altId = employeeId.startsWith('EMP')
            ? employeeId.substring(3)
            : 'EMP$employeeId';

        final altDoc = await FirebaseFirestore.instance
            .collection('fcm_tokens')
            .doc(altId)
            .get();

        if (altDoc.exists && altDoc.data()?['token'] != null) {
          String token = altDoc.data()!['token'];
          await _sendNotificationWithToken(altId, token, isApproved, message, requestType);
          return;
        }

        debugPrint("No FCM token found for employee $employeeId or alt format");
        return;
      }

      String? token = doc.data()?['token'];
      if (token == null) {
        debugPrint("FCM token is null for employee $employeeId");
        return;
      }

      await _sendNotificationWithToken(employeeId, token, isApproved, message, requestType);
    } catch (e) {
      debugPrint("Error sending notification: $e");
    }
  }

  Future<void> _sendNotificationWithToken(
      String employeeId, String token, bool isApproved, String? message, String requestType) async {
    try {
      // Format the request type for display - ensuring proper capitalization
      String displayType = requestType == 'check-in' ? 'Check-In' : 'Check-Out';

      // Send notification via Firebase Cloud Function
      await FirebaseFirestore.instance.collection('notifications').add({
        'token': token,
        'title': isApproved
            ? '$displayType Request Approved'
            : '$displayType Request Rejected',
        'body': isApproved
            ? 'Your request to ${requestType.replaceAll('-', ' ')} has been approved'
            : 'Your request to ${requestType.replaceAll('-', ' ')} has been rejected${message != null && message.isNotEmpty ? ": $message" : ""}',
        'data': {
          'type': 'check_out_request_response',
          'employeeId': employeeId,
          'approved': isApproved,
          'message': message ?? '',
          'requestType': requestType,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
        'sentAt': FieldValue.serverTimestamp(),
      });

      // Also send directly to the employee topic for better delivery chances
      await FirebaseFirestore.instance.collection('notifications').add({
        'topic': 'employee_$employeeId',
        'title': isApproved
            ? '$displayType Request Approved'
            : '$displayType Request Rejected',
        'body': isApproved
            ? 'Your request to ${requestType.replaceAll('-', ' ')} has been approved'
            : 'Your request to ${requestType.replaceAll('-', ' ')} has been rejected${message != null && message.isNotEmpty ? ": $message" : ""}',
        'data': {
          'type': 'check_out_request_response',
          'employeeId': employeeId,
          'approved': isApproved,
          'message': message ?? '',
          'requestType': requestType,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
        'sentAt': FieldValue.serverTimestamp(),
      });

      debugPrint("Notification scheduled for employee $employeeId for $requestType request");
    } catch (e) {
      debugPrint("Error sending notification with token: $e");
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
                  ? "Are you sure you want to approve this ${request.requestType.replaceAll('-', ' ')} request?"
                  : "Are you sure you want to reject this ${request.requestType.replaceAll('-', ' ')} request?",
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
    // Filter requests based on selected tab
    List<CheckOutRequest> filteredRequests = _filterType == 'all'
        ? _pendingRequests
        : _pendingRequests.where((req) => req.requestType == _filterType).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pending Approval Requests"),
        backgroundColor: scaffoldTopGradientClr,
        actions: [
          // Add debug buttons for troubleshooting
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _debugCheckManagerId,
            tooltip: "Debug Manager ID",
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _directFirestoreQuery,
            tooltip: "Direct Query",
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingRequests,
            tooltip: "Refresh",
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "All"),
            Tab(text: "Check-In"),
            Tab(text: "Check-Out"),
          ],
          labelColor: Colors.white,
          indicatorColor: Colors.white,
        ),
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
            : filteredRequests.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredRequests.length,
                    itemBuilder: (context, index) {
                      return _buildRequestCard(filteredRequests[index]);
                    },
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    String messageText = "No pending requests";
    if (_filterType == 'check-in') {
      messageText = "No pending check-in requests";
    } else if (_filterType == 'check-out') {
      messageText = "No pending check-out requests";
    }

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
            messageText,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "When employees request to ${_filterType == 'check-in' ? 'check in' : _filterType == 'check-out' ? 'check out' : 'check in/out'} from outside the office, their requests will appear here",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
          // Add manager ID debug info in empty state
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Debug Info",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Manager ID: ${widget.managerId}",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                Text(
                  "Also checking: ${widget.managerId.startsWith('EMP') ? widget.managerId.substring(3) : 'EMP${widget.managerId}'}",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Add refresh button
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadPendingRequests,
            icon: const Icon(Icons.refresh),
            label: const Text("Refresh"),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(CheckOutRequest request) {
    final dateFormat = DateFormat('EEE, MMM d, yyyy');
    final timeFormat = DateFormat('h:mm a');

    // Different colors based on request type
    final Color requestTypeColor = request.requestType == 'check-in' ? Colors.blue : Colors.purple;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Employee name, request type and time
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
                Row(
                  children: [
                    // Request type badge
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: requestTypeColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: requestTypeColor,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        request.requestType == 'check-in' ? "Check-In" : "Check-Out",
                        style: TextStyle(
                          color: requestTypeColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    // Time badge
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

            // Request ID (for debugging)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.vpn_key, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Request ID",
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        request.id,
                        style: const TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

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