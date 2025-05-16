// lib/checkout_request/request_history_view.dart

import 'package:flutter/material.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/model/check_out_request_model.dart';
import 'package:face_auth_compatible/repositories/check_out_request_repository.dart';
import 'package:face_auth_compatible/services/service_locator.dart';
import 'package:intl/intl.dart';

class CheckOutRequestHistoryView extends StatefulWidget {
  final String employeeId;

  const CheckOutRequestHistoryView({
    Key? key,
    required this.employeeId,
  }) : super(key: key);

  @override
  State<CheckOutRequestHistoryView> createState() => _CheckOutRequestHistoryViewState();
}

class _CheckOutRequestHistoryViewState extends State<CheckOutRequestHistoryView> {
  bool _isLoading = true;
  List<CheckOutRequest> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final repository = getIt<CheckOutRequestRepository>();
      final requests = await repository.getRequestsForEmployee(widget.employeeId);

      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (e) {
      print("Error loading requests: $e");
      setState(() {
        _isLoading = false;
      });
    }
  }

  Color _getStatusColor(CheckOutRequestStatus status) {
    switch (status) {
      case CheckOutRequestStatus.pending:
        return Colors.orange;
      case CheckOutRequestStatus.approved:
        return Colors.green;
      case CheckOutRequestStatus.rejected:
        return Colors.red;
    }
  }

  String _getStatusText(CheckOutRequestStatus status) {
    switch (status) {
      case CheckOutRequestStatus.pending:
        return "Pending";
      case CheckOutRequestStatus.approved:
        return "Approved";
      case CheckOutRequestStatus.rejected:
        return "Rejected";
    }
  }

  Icon _getStatusIcon(CheckOutRequestStatus status) {
    switch (status) {
      case CheckOutRequestStatus.pending:
        return const Icon(Icons.hourglass_empty, color: Colors.orange);
      case CheckOutRequestStatus.approved:
        return const Icon(Icons.check_circle, color: Colors.green);
      case CheckOutRequestStatus.rejected:
        return const Icon(Icons.cancel, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Check-Out Requests"),
        backgroundColor: scaffoldTopGradientClr,
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
            : _requests.isEmpty
            ? _buildEmptyState()
            : ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: _requests.length,
          itemBuilder: (context, index) {
            return _buildRequestCard(_requests[index]);
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
            Icons.history,
            size: 64,
            color: Colors.white.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            "No check-out requests yet",
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "When you request to check out from a location outside the office, it will appear here",
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
            // Status and date
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dateFormat.format(request.requestTime),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(request.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _getStatusColor(request.status),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _getStatusIcon(request.status),
                      const SizedBox(width: 4),
                      Text(
                        _getStatusText(request.status),
                        style: TextStyle(
                          color: _getStatusColor(request.status),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

            const SizedBox(height: 12),

            // Request and response time
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.access_time, size: 20, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Requested",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              timeFormat.format(request.requestTime),
                              style: const TextStyle(
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (request.responseTime != null)
                  Expanded(
                    child: Row(
                      children: [
                        Icon(
                          request.status == CheckOutRequestStatus.approved
                              ? Icons.check_circle
                              : Icons.cancel,
                          size: 20,
                          color: _getStatusColor(request.status),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                request.status == CheckOutRequestStatus.approved
                                    ? "Approved"
                                    : "Rejected",
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                timeFormat.format(request.responseTime!),
                                style: const TextStyle(
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            // Response message (if any)
            if (request.responseMessage != null && request.responseMessage!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      request.status == CheckOutRequestStatus.approved
                          ? Icons.comment
                          : Icons.comment_bank,
                      size: 20,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Manager Comment",
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            request.responseMessage!,
                            style: const TextStyle(
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // If approved, show check-out button
            if (request.status == CheckOutRequestStatus.approved)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: Handle check-out with approved request
                      Navigator.pop(context, {'requestId': request.id, 'approved': true});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text("Check Out Now"),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}