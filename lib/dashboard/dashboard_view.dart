// lib/dashboard/dashboard_view.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/pin_entry/pin_entry_view.dart';
import 'package:face_auth_compatible/dashboard/user_profile_page.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/utils/geofence_util.dart';
import 'package:face_auth_compatible/authenticate_face/authenticate_face_view.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:face_auth_compatible/model/location_model.dart';

class DashboardView extends StatefulWidget {
  final String employeeId;

  const DashboardView({Key? key, required this.employeeId}) : super(key: key);

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isDarkMode = false;
  Map<String, dynamic>? _userData;
  bool _isCheckedIn = false;
  DateTime? _checkInTime;
  String _formattedDate = '';
  String _currentTime = '';
  List<Map<String, dynamic>> _recentActivity = [];
  late TabController _tabController;
  LocationModel? _nearestLocation;
  List<LocationModel> _availableLocations = [];

  // Geofencing related variables
  bool _isCheckingLocation = false;
  bool _isWithinGeofence = false;
  double? _distanceToOffice;

  // Authentication related variables
  bool _isAuthenticating = false;

  @override
  void initState() {
    super.initState();
    _loadDarkModePreference();
    _fetchUserData();
    _fetchAttendanceStatus();
    _fetchRecentActivity();
    _tabController = TabController(length: 2, vsync: this);

    // Check geofence status when the dashboard loads
    _checkGeofenceStatus();

    // Initialize date and time
    _updateDateTime();

    // Set up a timer to update time every minute
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _updateDateTime();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Load dark mode preference
  Future<void> _loadDarkModePreference() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  // Save dark mode preference
  Future<void> _saveDarkModePreference(bool isDarkMode) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
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

  // Check if user is within geofence
  Future<void> _checkGeofenceStatus() async {
    if (!mounted) return;

    setState(() {
      _isCheckingLocation = true;
    });

    try {
      // Forcing the GPS to get fresh location data
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );

      // Get detailed geofence status with all locations
      Map<String, dynamic> status = await GeofenceUtil.checkGeofenceStatus(context);

      bool withinGeofence = status['withinGeofence'] as bool;
      LocationModel? nearestLocation = status['location'] as LocationModel?;
      double? distance = status['distance'] as double?;

      // Get all available locations for the status card
      List<LocationModel> locations = await GeofenceUtil.getActiveLocations(context);

      if (mounted) {
        setState(() {
          _isWithinGeofence = withinGeofence;
          _nearestLocation = nearestLocation;
          _distanceToOffice = distance;
          _availableLocations = locations;
          _isCheckingLocation = false;
        });
      }
    } catch (e) {
      debugPrint('Error checking geofence: $e');
      if (mounted) {
        setState(() {
          _isCheckingLocation = false;
        });
        CustomSnackBar.errorSnackBar("Error checking geofence status: $e");
      }
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

  Future<void> _fetchRecentActivity() async {
    try {
      // Get the last 5 attendance records
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .collection('attendance')
          .orderBy('date', descending: true)
          .limit(5)
          .get();

      List<Map<String, dynamic>> activity = [];
      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        activity.add({
          'date': data['date'],
          'checkIn': data['checkIn'],
          'checkOut': data['checkOut'],
          'workStatus': data['workStatus'],
          'totalHours': data['totalHours'],
          'location': data['location'] ?? 'Unknown',
        });
      }

      setState(() {
        _recentActivity = activity;
      });
    } catch (e) {
      print("Error fetching activity: $e");
    }
  }

  Future<void> _handleCheckInOut() async {
    // If already in authentication process, prevent multiple taps
    if (_isAuthenticating) {
      return;
    }

    // First, refresh the geofence status
    await _checkGeofenceStatus();

    if (!_isCheckedIn) {
      // For check-in, verify if within geofence
      if (!_isWithinGeofence) {
        CustomSnackBar.errorSnackBar(
            "You must be within the office premises to check in. " +
                "You are currently ${_distanceToOffice != null ? '${_distanceToOffice!.toStringAsFixed(0)} meters' : 'too far'} away from ${_nearestLocation?.name ?? 'the office'}."
        );
        return;
      }

      // Set authenticating flag to prevent multiple dialog opens
      setState(() {
        _isAuthenticating = true;
      });

      // Launch face authentication for check-in
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return WillPopScope(
            onWillPop: () async => false, // Prevent back button from closing dialog
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.8,
                child: AuthenticateFaceView(
                  employeeId: widget.employeeId,
                  onAuthenticationComplete: (bool success) async {
                    // Reset authenticating flag
                    setState(() {
                      _isAuthenticating = false;
                    });

                    // Close the dialog
                    Navigator.of(context).pop();

                    if (success) {
                      // If authentication successful, proceed with check-in
                      _completeCheckIn();
                    } else {
                      // If authentication failed, show error message
                      CustomSnackBar.errorSnackBar("Face authentication failed. Check-in canceled.");
                    }
                  },
                ),
              ),
            ),
          );
        },
      ).then((_) {
        // If dialog is dismissed without completing authentication
        if (_isAuthenticating) {
          setState(() {
            _isAuthenticating = false;
          });
        }
      });
    } else {
      // For check-out, still require face authentication for security
      setState(() {
        _isAuthenticating = true;
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return WillPopScope(
            onWillPop: () async => false, // Prevent back button from closing dialog
            child: Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.8,
                child: AuthenticateFaceView(
                  employeeId: widget.employeeId,
                  onAuthenticationComplete: (bool success) async {
                    // Reset authenticating flag
                    setState(() {
                      _isAuthenticating = false;
                    });

                    // Close the dialog
                    Navigator.of(context).pop();

                    if (success) {
                      // If authentication successful, proceed with check-out
                      _completeCheckOut();
                    } else {
                      // If authentication failed, show error message
                      CustomSnackBar.errorSnackBar("Face authentication failed. Check-out canceled.");
                    }
                  },
                ),
              ),
            ),
          );
        },
      ).then((_) {
        // If dialog is dismissed without completing authentication
        if (_isAuthenticating) {
          setState(() {
            _isAuthenticating = false;
          });
        }
      });
    }
  }

  // New method to complete check-in process after successful face auth
  Future<void> _completeCheckIn() async {
    try {
      setState(() => _isLoading = true);

      // Get today's date in YYYY-MM-DD format for the document ID
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      DateTime now = DateTime.now();

      // Get current position for logging
      Position? currentPosition = await GeofenceUtil.getCurrentPosition();

      // Reference to today's attendance document
      DocumentReference attendanceRef = FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .collection('attendance')
          .doc(today);

      // Check In data
      Map<String, dynamic> checkInData = {
        'date': today,
        'checkIn': Timestamp.fromDate(now),
        'checkOut': null,
        'workStatus': 'In Progress',
        'totalHours': 0,
        'location': _nearestLocation?.name ?? 'Unknown',
        'locationId': _nearestLocation?.id ?? 'default',
        'address': _nearestLocation?.address ?? 'Unknown',
        'isWithinGeofence': true,
      };

      // Add location coordinates if available
      if (currentPosition != null) {
        checkInData['locationLat'] = currentPosition.latitude;
        checkInData['locationLng'] = currentPosition.longitude;
        checkInData['locationAccuracy'] = currentPosition.accuracy;
      }

      await attendanceRef.set(checkInData, SetOptions(merge: true));

      setState(() {
        _isCheckedIn = true;
        _checkInTime = now;
        _isLoading = false;
      });

      CustomSnackBar.successSnackBar("Checked in successfully at $_currentTime");

      // Refresh activity list
      _fetchRecentActivity();
    } catch (e) {
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar("Error updating attendance: $e");
      debugPrint('CheckIn Error: $e');
    }
  }

  // New method to handle check-out process
  Future<void> _completeCheckOut() async {
    try {
      setState(() => _isLoading = true);

      // Get today's date in YYYY-MM-DD format for the document ID
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      DateTime now = DateTime.now();

      // Calculate hours worked
      double hoursWorked = _checkInTime != null
          ? now.difference(_checkInTime!).inMinutes / 60
          : 0;

      // Get current position for logging
      Position? currentPosition = await GeofenceUtil.getCurrentPosition();

      // Reference to today's attendance document
      DocumentReference attendanceRef = FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .collection('attendance')
          .doc(today);

      Map<String, dynamic> checkOutData = {
        'checkOut': Timestamp.fromDate(now),
        'workStatus': 'Completed',
        'totalHours': hoursWorked,
      };

      // Add location coordinates if available
      if (currentPosition != null) {
        checkOutData['checkoutLocationLat'] = currentPosition.latitude;
        checkOutData['checkoutLocationLng'] = currentPosition.longitude;
      }

      await attendanceRef.update(checkOutData);

      setState(() {
        _isCheckedIn = false;
        _checkInTime = null;
        _isLoading = false;
      });

      CustomSnackBar.successSnackBar("Checked out successfully at $_currentTime");

      // Refresh activity list
      _fetchRecentActivity();
    } catch (e) {
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar("Error updating attendance: $e");
      debugPrint('CheckOut Error: $e');
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
    // Set context for snackbar
    if (CustomSnackBar.context == null) {
      CustomSnackBar.context = context;
    }

    return Scaffold(
      backgroundColor: _isDarkMode ? const Color(0xFF121212) : Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: accentColor))
          : SafeArea(
        child: Column(
          children: [
            // Profile header
            _buildProfileHeader(),

            // Date and time
            _buildDateTimeWithoutStrip(),

            // Status card
            _buildStatusCard(),

            // Tabs and content
            Expanded(
              child: _buildTabbedContent(),
            ),
          ],
        ),
      ),
      // Add floating action button to refresh geofence status
      floatingActionButton: FloatingActionButton(
        onPressed: _checkGeofenceStatus,
        tooltip: 'Refresh Location',
        backgroundColor: accentColor,
        child: const Icon(Icons.refresh_rounded),
      ),
    );
  }

  Widget _buildProfileHeader() {
    String name = _userData?['name'] ?? 'User';
    String designation = _userData?['designation'] ?? 'Employee';
    String? imageBase64 = _userData?['image'];

    return Container(
      padding: const EdgeInsets.all(16.0),
      color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      child: Row(
        children: [
          // Profile image
          CircleAvatar(
            radius: 25,
            backgroundColor: _isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
            backgroundImage: imageBase64 != null
                ? MemoryImage(base64Decode(imageBase64))
                : null,
            child: imageBase64 == null
                ? Icon(
              Icons.person,
              color: _isDarkMode ? Colors.grey.shade300 : Colors.grey,
            )
                : null,
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
                    color: _isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  designation,
                  style: TextStyle(
                    color: _isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // Settings icon
          IconButton(
            icon: Icon(
              Icons.settings_outlined,
              color: _isDarkMode ? Colors.white : Colors.black,
            ),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeWithoutStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      child: Row(
        children: [
          Icon(
              Icons.calendar_today,
              size: 16,
              color: _isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600
          ),
          const SizedBox(width: 8),
          Text(
            _formattedDate,
            style: TextStyle(
              fontSize: 14,
              color: _isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
          const Spacer(),
          Icon(
              Icons.access_time,
              size: 16,
              color: _isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600
          ),
          const SizedBox(width: 4),
          Text(
            _currentTime,
            style: TextStyle(
              fontSize: 14,
              color: _isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final String locationName = _nearestLocation?.name ?? 'office location';

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF2D2D3A) : const Color(0xFF8D8AD3),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status information
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left side - Status text
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Today's Status",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isCheckedIn ? "Checked In" : "Not Started",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_isCheckedIn && _checkInTime != null)
                      Text(
                        "Since ${DateFormat('h:mm a').format(_checkInTime!)}",
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),

                // Right side - Status indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isCheckedIn
                        ? Colors.green.withOpacity(0.3)
                        : Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isCheckedIn ? Icons.check_circle : Icons.schedule,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isCheckedIn ? "Checked in" : "Not checked in",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Geofence status indicator with location name
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(
                  _isWithinGeofence ? Icons.location_on : Icons.location_off,
                  color: _isWithinGeofence ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isCheckingLocation
                        ? "Checking location..."
                        : _isWithinGeofence
                        ? "You are at $locationName"
                        : "You are outside $locationName" +
                        (_distanceToOffice != null
                            ? " (${_distanceToOffice!.toStringAsFixed(0)}m away)"
                            : ""),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                ),
                if (_isCheckingLocation)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
              ],
            ),
          ),

          // Available locations list (if more than one)
          if (_availableLocations.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Available Check-in Locations:",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...List.generate(
                    _availableLocations.length,
                        (index) {
                      final location = _availableLocations[index];
                      final isNearest = _nearestLocation?.id == location.id;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Icon(
                              isNearest ? Icons.star : Icons.location_on_outlined,
                              color: isNearest ? Colors.amber : Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                location.name,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 12,
                                  fontWeight: isNearest ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

          // Check In/Out button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading || _isAuthenticating || (!_isCheckedIn && !_isWithinGeofence)
                    ? null  // Disable button during loading, authentication, or if outside geofence
                    : _handleCheckInOut,
                style: ElevatedButton.styleFrom(
                  backgroundColor: (!_isCheckedIn && !_isWithinGeofence) || _isLoading || _isAuthenticating
                      ? Colors.grey
                      : _isCheckedIn
                      ? const Color(0xFFEC407A) // Pink for check out
                      : const Color(0xFF4CAF50), // Green for check in
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: _isLoading || _isAuthenticating
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Check In/Out icon
                    Icon(
                      _isCheckedIn ? Icons.exit_to_app : Icons.login,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isCheckedIn ? "CHECK OUT WITH FACE ID" : "CHECK IN WITH FACE ID",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabbedContent() {
    return Column(
      children: [
        // Tab bar
        Container(
          color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          child: TabBar(
            controller: _tabController,
            labelColor: accentColor,
            unselectedLabelColor: _isDarkMode ? Colors.grey.shade400 : Colors.grey,
            indicatorColor: accentColor,
            tabs: const [
              Tab(text: "Recent Activity"),
              Tab(text: "Menu"),
            ],
          ),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildRecentActivityTab(),
              _buildMenuTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecentActivityTab() {
    // Background color based on theme
    Color bgColor = _isDarkMode ? const Color(0xFF121212) : Colors.grey.shade100;

    // Show empty state with your specific NODATA.svg asset
    if (_recentActivity.isEmpty) {
      return Container(
        color: bgColor,
        child: Center(
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SvgPicture.asset(
            'assets/images/NODATA.svg', // Your specific asset
            height: 120,
            width: 120,
            placeholderBuilder: (context) => Icon(
              Icons.calendar_today_outlined,
              size: 80,
              color: _isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            "No activity records found",
            style: TextStyle(
              color: _isDarkMode ? Colors.grey.shade400 : Colors.grey,
              fontSize: 16,
            ),
          ),
        ],
      ),
        ),
      );
    }

    // Show activity list if data exists
    return Container(
      color: bgColor,
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: _recentActivity.length,
        itemBuilder: (context, index) {
          // Activity list item implementation
          Map<String, dynamic> activity = _recentActivity[index];
          String date = activity['date'] ?? 'Unknown';
          DateTime? checkIn = activity['checkIn'] != null
              ? (activity['checkIn'] as Timestamp).toDate()
              : null;
          DateTime? checkOut = activity['checkOut'] != null
              ? (activity['checkOut'] as Timestamp).toDate()
              : null;
          String status = activity['workStatus'] ?? 'Unknown';
          String location = activity['location'] ?? 'Unknown';

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: _isDarkMode ? const Color(0xFF2A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              title: Text(
                _formatDisplayDate(date),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: _isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        checkIn != null
                            ? 'In: ${DateFormat('h:mm a').format(checkIn)}'
                            : 'Not checked in',
                        style: TextStyle(
                            fontSize: 12,
                            color: _isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        checkOut != null
                            ? 'Out: ${DateFormat('h:mm a').format(checkOut)}'
                            : 'Not checked out',
                        style: TextStyle(
                            fontSize: 12,
                            color: _isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Location: $location',
                    style: TextStyle(
                        fontSize: 12,
                        color: _isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600
                    ),
                  ),
                ],
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(_isDarkMode ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: _getStatusColor(status),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuTab() {
    return Container(
      color: _isDarkMode ? const Color(0xFF121212) : Colors.grey.shade100,
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
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
                _saveDarkModePreference(value);
              });
            },
          ),

          _buildMenuOption(
            icon: Icons.location_on_outlined,
            title: 'Geofence Status',
            subtitle: _isCheckingLocation
                ? 'Checking location...'
                : _isWithinGeofence
                ? 'Within office area'
                : 'Outside office area',
            onTap: _checkGeofenceStatus,
            showStatusIcon: true,
            statusIcon: _isWithinGeofence ? Icons.check_circle : Icons.cancel,
            statusColor: _isWithinGeofence ? Colors.green : Colors.red,
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

          const SizedBox(height: 20),

          // Coming soon section
          Center(
            child: Column(
              children: [
                SvgPicture.asset(
                  'assets/images/under_development.svg',
                  height: 60,
                  width: 60,
                  placeholderBuilder: (context) => Icon(
                    Icons.construction,
                    size: 60,
                    color: _isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Additional features coming soon!',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
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
    String? subtitle,
    VoidCallback? onTap,
    bool hasToggle = false,
    bool toggleValue = false,
    Function(bool)? onToggleChanged,
    Color iconColor = Colors.black54,
    Color textColor = Colors.black87,
    bool showStatusIcon = false,
    IconData? statusIcon,
    Color? statusColor,
  }) {
    // Adjust colors for dark mode
    if (_isDarkMode) {
      if (iconColor == Colors.black54) iconColor = Colors.white70;
      if (textColor == Colors.black87) textColor = Colors.white;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
        ),
      ),
      child: InkWell(
        onTap: hasToggle ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isDarkMode
                      ? Colors.black.withOpacity(0.3)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: _isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showStatusIcon && statusIcon != null)
                Icon(
                  statusIcon,
                  color: statusColor,
                  size: 16,
                ),
              if (hasToggle)
                Switch(
                  value: toggleValue,
                  onChanged: onToggleChanged,
                  activeColor: accentColor,
                )
              else if (!showStatusIcon)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: _isDarkMode ? Colors.grey.shade600 : Colors.grey,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDisplayDate(String dateStr) {
    try {
      // Assuming dateStr is in format yyyy-MM-dd
      DateTime date = DateFormat('yyyy-MM-dd').parse(dateStr);

      // If it's today
      if (DateFormat('yyyy-MM-dd').format(DateTime.now()) == dateStr) {
        return 'Today';
      }

      // If it's yesterday
      DateTime yesterday = DateTime.now().subtract(const Duration(days: 1));
      if (DateFormat('yyyy-MM-dd').format(yesterday) == dateStr) {
        return 'Yesterday';
      }

      // Otherwise return formatted date
      return DateFormat('MMM d, yyyy').format(date);
    } catch (e) {
      return dateStr; // Return original if parsing fails
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'in progress':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  void _showComingSoonDialog(String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDarkMode ? const Color(0xFF2A2A2A) : Colors.white,
        title: Text(
          'Coming Soon',
          style: TextStyle(
            color: _isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/images/under_development.svg',
              height: 100,
              width: 100,
              placeholderBuilder: (context) => Icon(
                Icons.construction,
                size: 80,
                color: _isDarkMode ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'The $feature feature is coming soon!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: _isDarkMode ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }
}

