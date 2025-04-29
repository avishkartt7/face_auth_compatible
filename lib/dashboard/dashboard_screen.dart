// lib/dashboard/dashboard_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/authenticate_face/authenticate_face_view.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/common/utils/extensions/size_extension.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends StatefulWidget {
  final String employeeId;
  final Map<String, dynamic> employeeData;

  const DashboardScreen({
    Key? key,
    required this.employeeId,
    required this.employeeData,
  }) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = false;
  bool _isCheckedIn = false;
  String _lastCheckInTime = 'Not checked in today';
  String _workDuration = '';

  @override
  void initState() {
    super.initState();
    _checkTodayAttendance();
  }

  Future<void> _checkTodayAttendance() async {
    setState(() => _isLoading = true);

    try {
      // Get today's date in YYYY-MM-DD format for querying
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Check if employee has checked in today
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .collection('attendance')
          .where('date', isEqualTo: today)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final attendanceData = snapshot.docs.first.data() as Map<String, dynamic>;
        setState(() {
          _isCheckedIn = attendanceData['checkInTime'] != null;
          if (_isCheckedIn) {
            _lastCheckInTime = _formatTimestamp(attendanceData['checkInTime']);

            // If checked out, calculate duration
            if (attendanceData['checkOutTime'] != null) {
              DateTime checkIn = (attendanceData['checkInTime'] as Timestamp).toDate();
              DateTime checkOut = (attendanceData['checkOutTime'] as Timestamp).toDate();
              Duration duration = checkOut.difference(checkIn);
              _workDuration = _formatDuration(duration);
              _isCheckedIn = false; // Already checked out
            }
          }
        });
      }
    } catch (e) {
      CustomSnackBar.errorSnackBar("Error loading attendance: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'N/A';
    DateTime dateTime = (timestamp as Timestamp).toDate();
    return DateFormat('hh:mm a').format(dateTime);
  }

  String _formatDuration(Duration duration) {
    int hours = duration.inHours;
    int minutes = duration.inMinutes.remainder(60);
    return '$hours hrs $minutes mins';
  }

  @override
  Widget build(BuildContext context) {
    // Initialize context
    CustomSnackBar.context = context;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF7C4DFF), // Deep purple
              Color(0xFF5E72E4), // Indigo
              Color(0xFF4FB0FF), // Light blue
            ],
            stops: [0.1, 0.5, 0.9],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : Column(
            children: [
              // App bar
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 0.06.sw,
                  vertical: 0.02.sh,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Dashboard",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 0.06.sw,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: _showProfileOptions,
                      icon: CircleAvatar(
                        radius: 0.06.sw,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        child: Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 0.05.sw,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Employee info card
              Container(
                margin: EdgeInsets.all(0.05.sw),
                padding: EdgeInsets.all(0.05.sw),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 0.1.sw,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      child: Text(
                        widget.employeeData['name']?.substring(0, 1).toUpperCase() ?? 'E',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 0.08.sw,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(height: 0.02.sh),
                    Text(
                      widget.employeeData['name'] ?? 'Employee',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 0.055.sw,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 0.01.sh),
                    Text(
                      "${widget.employeeData['designation'] ?? 'Staff'} - ${widget.employeeData['department'] ?? 'Department'}",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 0.04.sw,
                      ),
                    ),
                    SizedBox(height: 0.02.sh),

                    // Attendance status
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 0.04.sw,
                        vertical: 0.01.sh,
                      ),
                      decoration: BoxDecoration(
                        color: _isCheckedIn ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isCheckedIn ? Colors.green.withOpacity(0.6) : Colors.red.withOpacity(0.6),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        _isCheckedIn ? "Checked In" : "Not Checked In",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    SizedBox(height: 0.02.sh),

                    // Last check-in/out info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          color: Colors.white.withOpacity(0.8),
                          size: 0.04.sw,
                        ),
                        SizedBox(width: 0.01.sw),
                        Text(
                          _lastCheckInTime,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 0.035.sw,
                          ),
                        ),
                      ],
                    ),

                    if (_workDuration.isNotEmpty) ...[
                      SizedBox(height: 0.01.sh),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.timelapse_rounded,
                            color: Colors.white.withOpacity(0.8),
                            size: 0.04.sw,
                          ),
                          SizedBox(width: 0.01.sw),
                          Text(
                            "Work duration: $_workDuration",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 0.035.sw,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Today's date
              Padding(
                padding: EdgeInsets.symmetric(vertical: 0.02.sh),
                child: Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 0.045.sw,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              // Check-in/out buttons
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 0.1.sw),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        label: "Check In",
                        icon: Icons.login_rounded,
                        isActive: !_isCheckedIn,
                        onTap: _isCheckedIn ? null : _handleCheckIn,
                      ),
                    ),
                    SizedBox(width: 0.05.sw),
                    Expanded(
                      child: _buildActionButton(
                        label: "Check Out",
                        icon: Icons.logout_rounded,
                        isActive: _isCheckedIn,
                        onTap: _isCheckedIn ? _handleCheckOut : null,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Attendance history button
              Padding(
                padding: EdgeInsets.only(
                  left: 0.05.sw,
                  right: 0.05.sw,
                  bottom: 0.04.sh,
                ),
                child: GestureDetector(
                  onTap: _viewAttendanceHistory,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 0.06.sw,
                      vertical: 0.025.sh,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history_rounded,
                          color: Colors.white,
                          size: 0.06.sw,
                        ),
                        SizedBox(width: 0.02.sw),
                        Text(
                          "View Attendance History",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 0.045.sw,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 0.04.sw,
          vertical: 0.03.sh,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white
              : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isActive
                  ? const Color(0xFF5E72E4)
                  : Colors.white.withOpacity(0.5),
              size: 0.08.sw,
            ),
            SizedBox(height: 0.01.sh),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? const Color(0xFF5E72E4)
                    : Colors.white.withOpacity(0.5),
                fontSize: 0.04.sw,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleCheckIn() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AuthenticateFaceView(
          employeeId: widget.employeeId,
          isCheckIn: true,
        ),
      ),
    ).then((_) => _checkTodayAttendance());
  }

  void _handleCheckOut() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AuthenticateFaceView(
          employeeId: widget.employeeId,
          isCheckOut: true,
        ),
      ),
    ).then((_) => _checkTodayAttendance());
  }

  void _viewAttendanceHistory() {
    // This will be implemented later
    CustomSnackBar.successSnackBar("Attendance history feature coming soon!");
  }

  void _showProfileOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.all(0.05.sw),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person, color: Color(0xFF5E72E4)),
              title: const Text("View Profile"),
              onTap: () {
                Navigator.pop(context);
                // Navigate to profile view (to be implemented)
              },
            ),
            ListTile(
              leading: const Icon(Icons.password, color: Color(0xFF5E72E4)),
              title: const Text("Change Password"),
              onTap: () {
                Navigator.pop(context);
                // Navigate to change password view (to be implemented)
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Logout", style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // Go back to login screen
              Navigator.of(context).pushReplacementNamed('/login');
            },
            child: const Text("Logout", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}