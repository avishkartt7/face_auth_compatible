// lib/dashboard/user_dashboard.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/common/utils/extensions/size_extension.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/dashboard/check_in_out_view.dart'; // We'll create this later
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class UserDashboard extends StatefulWidget {
  final String employeeId;
  final Map<String, dynamic> employeeData;

  const UserDashboard({
    Key? key,
    required this.employeeId,
    required this.employeeData,
  }) : super(key: key);

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  late String _greeting;
  bool _isCheckedIn = false;
  Timestamp? _lastCheckInTime;

  @override
  void initState() {
    super.initState();
    _updateGreeting();
    _checkAttendanceStatus();
  }

  void _updateGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      _greeting = "Good Morning";
    } else if (hour < 17) {
      _greeting = "Good Afternoon";
    } else {
      _greeting = "Good Evening";
    }
  }

  Future<void> _checkAttendanceStatus() async {
    try {
      // Get today's date at midnight
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Query Firestore for today's attendance records
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .where('employeeId', isEqualTo: widget.employeeId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
          .orderBy('date', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final attendance = snapshot.docs.first.data() as Map<String, dynamic>;
        setState(() {
          _isCheckedIn = attendance['checkOutTime'] == null;
          _lastCheckInTime = attendance['checkInTime'] as Timestamp?;
        });
      }
    } catch (e) {
      CustomSnackBar.errorSnackBar("Error checking attendance status: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.employeeData['name'] ?? 'Employee';
    final department = widget.employeeData['department'] ?? 'Department';
    final designation = widget.employeeData['designation'] ?? 'Designation';

    return Scaffold(
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
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.all(0.04.sw),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 0.06.sh,
                      backgroundColor: primaryWhite.withOpacity(0.2),
                      child: Icon(
                        Icons.person,
                        size: 0.08.sh,
                        color: primaryWhite,
                      ),
                    ),
                    SizedBox(width: 0.04.sw),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "$_greeting,",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 0.005.sh),
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 0.005.sh),
                          Text(
                            "$designation, $department",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout, color: Colors.white),
                      onPressed: () {
                        // Handle logout
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
              SizedBox(height: 0.02.sh),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(0.04.sh),
                      topRight: Radius.circular(0.04.sh),
                    ),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(0.04.sw),
                        child: Row(
                          children: [
                            _buildStatusCard(
                              title: "Status",
                              content: _isCheckedIn ? "Checked In" : "Checked Out",
                              icon: _isCheckedIn ? Icons.login : Icons.logout,
                              color: _isCheckedIn ? Colors.green : Colors.red,
                            ),
                            SizedBox(width: 0.04.sw),
                            _buildStatusCard(
                              title: "Last Check-in",
                              content: _lastCheckInTime != null
                                  ? DateFormat('hh:mm a').format(_lastCheckInTime!.toDate())
                                  : "Not Available",
                              icon: Icons.access_time,
                              color: Colors.blue,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 0.02.sh),
                      _buildCheckInOutButton(),
                      SizedBox(height: 0.04.sh),
                      Expanded(
                        child: _buildAttendanceHistory(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard({
    required String title,
    required String content,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(0.04.sw),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                SizedBox(width: 0.02.sw),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            SizedBox(height: 0.01.sh),
            Text(
              content,
              style: TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckInOutButton() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CheckInOutView(
              employeeId: widget.employeeId,
              isCheckIn: !_isCheckedIn,
              onComplete: () {
                // Refresh dashboard data after check-in/out
                _checkAttendanceStatus();
              },
            ),
          ),
        );
      },
      child: Container(
        width: 0.8.sw,
        padding: EdgeInsets.symmetric(vertical: 0.02.sh),
        decoration: BoxDecoration(
          color: _isCheckedIn ? Colors.red : accentColor,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isCheckedIn ? Icons.logout : Icons.login,
              color: Colors.white,
            ),
            SizedBox(width: 0.02.sw),
            Text(
              _isCheckedIn ? "Check Out" : "Check In",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceHistory() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 0.04.sw),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Recent Attendance",
            style: TextStyle(
              color: Colors.black87,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 0.02.sh),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('attendance')
                  .where('employeeId', isEqualTo: widget.employeeId)
                  .orderBy('date', descending: true)
                  .limit(10)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text("Error: ${snapshot.error}"),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("No attendance records found"),
                  );
                }

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final record = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                    final date = (record['date'] as Timestamp).toDate();
                    final checkInTime = (record['checkInTime'] as Timestamp).toDate();
                    final checkOutTime = record['checkOutTime'] != null
                        ? (record['checkOutTime'] as Timestamp).toDate()
                        : null;

                    // Calculate duration if checked out
                    String duration = "In progress";
                    if (checkOutTime != null) {
                      final diff = checkOutTime.difference(checkInTime);
                      final hours = diff.inHours;
                      final minutes = diff.inMinutes % 60;
                      duration = "$hours hr ${minutes.toString().padLeft(2, '0')} min";
                    }

                    return Card(
                      margin: EdgeInsets.only(bottom: 0.02.sh),
                      child: ListTile(
                        title: Text(
                          DateFormat('MMM dd, yyyy').format(date),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 0.01.sh),
                            Row(
                              children: [
                                const Icon(
                                  Icons.login,
                                  color: Colors.green,
                                  size: 16,
                                ),
                                SizedBox(width: 0.01.sw),
                                Text(
                                  "In: ${DateFormat('hh:mm a').format(checkInTime)}",
                                ),
                              ],
                            ),
                            if (checkOutTime != null) ...[
                              SizedBox(height: 0.005.sh),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.logout,
                                    color: Colors.red,
                                    size: 16,
                                  ),
                                  SizedBox(width: 0.01.sw),
                                  Text(
                                    "Out: ${DateFormat('hh:mm a').format(checkOutTime)}",
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              duration,
                              style: TextStyle(
                                color: checkOutTime != null ? Colors.black87 : Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}