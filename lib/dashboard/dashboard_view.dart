// lib/dashboard/dashboard_view.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/pin_entry/pin_entry_view.dart';
import 'package:face_auth_compatible/dashboard/user_profile_page.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class DashboardView extends StatefulWidget {
  final String employeeId;

  const DashboardView({Key? key, required this.employeeId}) : super(key: key);

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  bool _isLoading = true;
  bool _isDarkMode = false;
  Map<String, dynamic>? _userData;
  bool _isCheckedIn = false;
  DateTime? _checkInTime;
  String _formattedDate = '';
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _fetchAttendanceStatus();

    // Initialize date and time
    _updateDateTime();

    // Set up a timer to update time every minute
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _updateDateTime();
    });
  }

  void _updateDateTime() {
    if (mounted) {
      setState(() {
        final now = DateTime.now();
        _formattedDate = DateFormat('EEEE, MMMM d, yyyy').format(now);
        _currentTime = DateFormat('h:mm a').format(now);
      });

      // Update time every minute
      Future.delayed(const Duration(minutes: 1), _updateDateTime);
    }
  }

  Future<void> _fetchUserData() async {
    try {
      DocumentSnapshot snapshot = await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .get();

      if (snapshot.exists) {
        setState(() {
          _userData = snapshot.data() as Map<String, dynamic>;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        CustomSnackBar.errorSnackBar("User data not found");
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      CustomSnackBar.errorSnackBar("Error fetching user data: $e");
    }
  }

  Future<void> _fetchAttendanceStatus() async {
    try {
      // Get today's date in YYYY-MM-DD format for the document ID
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      DocumentSnapshot attendanceDoc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .collection('attendance')
          .doc(today)
          .get();

      if (attendanceDoc.exists) {
        Map<String, dynamic> data = attendanceDoc.data() as Map<String, dynamic>;
        setState(() {
          _isCheckedIn = data['checkIn'] != null;
          if (_isCheckedIn) {
            _checkInTime = (data['checkIn'] as Timestamp).toDate();
          }
        });
      } else {
        setState(() {
          _isCheckedIn = false;
          _checkInTime = null;
        });
      }
    } catch (e) {
      print("Error fetching attendance: $e");
    }
  }

  Future<void> _handleCheckInOut() async {
    try {
      // Get today's date in YYYY-MM-DD format for the document ID
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      DateTime now = DateTime.now();

      // Reference to today's attendance document
      DocumentReference attendanceRef = FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .collection('attendance')
          .doc(today);

      if (!_isCheckedIn) {
        // Check In
        await attendanceRef.set({
          'date': today,
          'checkIn': Timestamp.fromDate(now),
          'checkOut': null,
          'workStatus': 'In Progress',
        }, SetOptions(merge: true));

        setState(() {
          _isCheckedIn = true;
          _checkInTime = now;
        });

        CustomSnackBar.successSnackBar("Checked in successfully at $_currentTime");
      } else {
        // Check Out
        await attendanceRef.update({
          'checkOut': Timestamp.fromDate(now),
          'workStatus': 'Completed',
          'totalHours': _checkInTime != null
              ? now.difference(_checkInTime!).inMinutes / 60
              : 0,
        });

        setState(() {
          _isCheckedIn = false;
          _checkInTime = null;
        });

        CustomSnackBar.successSnackBar("Checked out successfully at $_currentTime");
      }
    } catch (e) {
      CustomSnackBar.errorSnackBar("Error updating attendance: $e");
    }
  }

  Future<void> _logout() async {
    // Show confirmation dialog
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Logout", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      try {
        // Clear any local authentication tokens/flags
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('authenticated_user_id');

        // Navigate to login screen
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const PinEntryView(),
            ),
                (route) => false,
          );
        }
      } catch (e) {
        CustomSnackBar.errorSnackBar("Error during logout: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: accentColor))
          : Container(
        decoration: BoxDecoration(
          color: _isDarkMode ? Colors.black : Colors.white,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Profile header
              _buildProfileHeader(),

              // Dashboard content
              Expanded(
                child: _buildDashboardContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    String name = _userData?['name'] ?? 'User';
    String designation = _userData?['designation'] ?? 'Employee';
    String? imageBase64 = _userData?['image'];

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          // User image
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => UserProfilePage(
                    employeeId: widget.employeeId,
                    userData: _userData!,
                  ),
                ),
              );
            },
            child: Hero(
              tag: 'profile-${widget.employeeId}',
              child: CircleAvatar(
                radius: 30,
                backgroundColor: Colors.white.withOpacity(0.3),
                child: imageBase64 != null
                    ? ClipOval(
                  child: Image.memory(
                    base64Decode(imageBase64),
                    fit: BoxFit.cover,
                    width: 60,
                    height: 60,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.person,
                        size: 30,
                        color: Colors.white,
                      );
                    },
                  ),
                )
                    : const Icon(
                  Icons.person,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // User info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
                Text(
                  name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  designation,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          // Settings icon
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              _showComingSoonDialog('Settings');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),

          // Date and time
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formattedDate,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    _currentTime,
                    style: TextStyle(
                      fontSize: 14,
                      color: _isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
              // Attendance status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _isCheckedIn ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isCheckedIn ? Colors.green : Colors.orange,
                    width: 1,
                  ),
                ),
                child: Text(
                  _isCheckedIn ? "Checked In" : "Not Checked In",
                  style: TextStyle(
                    color: _isCheckedIn ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          // Check-in/Check-out button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _handleCheckInOut,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isCheckedIn ? Colors.redAccent : accentColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _isCheckedIn ? "CHECK OUT" : "CHECK IN",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          if (_isCheckedIn) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                "Checked in at ${_checkInTime != null ? DateFormat('h:mm a').format(_checkInTime!) : ''}",
                style: TextStyle(
                  color: _isDarkMode ? Colors.white70 : Colors.black54,
                  fontSize: 14,
                ),
              ),
            ),
          ],

          const SizedBox(height: 30),

          // Menu options
          _buildMenuOption(
            icon: Icons.person_outline,
            title: 'Profile details',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => UserProfilePage(
                    employeeId: widget.employeeId,
                    userData: _userData!,
                  ),
                ),
              );
            },
          ),

          _buildMenuOption(
            icon: Icons.dark_mode_outlined,
            title: 'Dark mode',
            hasToggle: true,
            toggleValue: _isDarkMode,
            onToggleChanged: (value) {
              setState(() {
                _isDarkMode = value;
              });
            },
          ),

          _buildMenuOption(
            icon: Icons.settings_outlined,
            title: 'Settings',
            onTap: () {
              _showComingSoonDialog('Settings');
            },
          ),

          _buildMenuOption(
            icon: Icons.logout,
            title: 'Log out',
            textColor: Colors.red,
            iconColor: Colors.red,
            onTap: _logout,
          ),

          const Spacer(),

          // Additional features coming soon
          Center(
            child: Column(
              children: [
                SvgPicture.asset(
                  'assets/images/under_development.svg',
                  height: 120,
                  width: 120,
                ),
                const SizedBox(height: 12),
                Text(
                  'Additional features coming soon!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: _isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuOption({
    required IconData icon,
    required String title,
    VoidCallback? onTap,
    bool hasToggle = false,
    bool toggleValue = false,
    Function(bool)? onToggleChanged,
    Color iconColor = Colors.black54,
    Color textColor = Colors.black87,
  }) {
    return InkWell(
      onTap: hasToggle ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(
              icon,
              color: _isDarkMode ? Colors.white70 : iconColor,
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: _isDarkMode ? Colors.white : textColor,
              ),
            ),
            const Spacer(),
            if (hasToggle)
              Switch(
                value: toggleValue,
                onChanged: onToggleChanged,
                activeColor: accentColor,
              )
            else
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: _isDarkMode ? Colors.white30 : Colors.black38,
              ),
          ],
        ),
      ),
    );
  }

  void _showComingSoonDialog(String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Coming Soon'),
        content: Text('The $feature feature is coming soon!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}