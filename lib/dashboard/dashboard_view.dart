// lib/dashboard/dashboard_view.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Add this for kDebugMode
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
import 'package:face_auth_compatible/dashboard/team_management_view.dart';
import 'package:face_auth_compatible/dashboard/checkout_handler.dart';
import 'package:face_auth_compatible/checkout_request/manager_pending_requests_view.dart';
import 'package:face_auth_compatible/checkout_request/request_history_view.dart';
import 'package:face_auth_compatible/repositories/check_out_request_repository.dart';
import 'package:face_auth_compatible/services/notification_service.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';
import 'package:face_auth_compatible/common/widgets/connectivity_banner.dart';
import 'package:face_auth_compatible/repositories/attendance_repository.dart';
import 'package:face_auth_compatible/repositories/location_repository.dart';
import 'package:face_auth_compatible/services/sync_service.dart';
import 'package:face_auth_compatible/services/service_locator.dart';
import 'package:face_auth_compatible/test/offline_test_view.dart';
import 'package:face_auth_compatible/dashboard/check_in_out_handler.dart';
import 'package:face_auth_compatible/services/fcm_token_service.dart'; // Add this for FcmTokenService

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
  bool _isLineManager = false;
  String? _lineManagerDocumentId; // Add this line
  Map<String, dynamic>? _lineManagerData;
  int _pendingApprovalRequests = 0;

  // Geofencing related variables
  bool _isCheckingLocation = false;
  bool _isWithinGeofence = false;
  double? _distanceToOffice;

  // Authentication related variables
  bool _isAuthenticating = false;

  // New variables for offline support
  late ConnectivityService _connectivityService;
  late AttendanceRepository _attendanceRepository;
  late LocationRepository _locationRepository;
  late SyncService _syncService;
  bool _needsSync = false;

  // Add lifecycle observer variable
  late AppLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _loadDarkModePreference();

    // Initialize notification services
    _initializeNotifications();

    final notificationService = getIt<NotificationService>();
    notificationService.notificationStream.listen(_handleNotification);

    // Get instances from service locator
    _connectivityService = getIt<ConnectivityService>();
    _attendanceRepository = getIt<AttendanceRepository>();
    _locationRepository = getIt<LocationRepository>();
    _syncService = getIt<SyncService>();

    // Listen to connectivity changes to show sync status
    _connectivityService.connectionStatusStream.listen((status) {
      debugPrint("Connectivity status changed: $status");
      if (status == ConnectionStatus.online && _needsSync) {
        _syncService.syncData().then((_) {
          // Refresh data after sync
          _fetchUserData();
          if (_isLineManager) {
            _loadPendingApprovalRequests();
          }
          _fetchAttendanceStatus();
          _fetchRecentActivity();
          setState(() {
            _needsSync = false;
          });
        });
      }
    });

    // Create and add the app lifecycle observer
    _lifecycleObserver = AppLifecycleObserver(
      onResume: () async {
        debugPrint("App resumed - refreshing dashboard");
        await _refreshDashboard();
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver);

    // Rest of your initialization code
    _fetchUserData();
    _fetchAttendanceStatus();
    _fetchRecentActivity();
    _tabController = TabController(length: 2, vsync: this);
    _checkGeofenceStatus();
    _updateDateTime();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) _updateDateTime();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    _tabController.dispose();
    _syncService.dispose();
    super.dispose();
  }

  void _handleNotification(Map<String, dynamic> data) {
    // Handle different notification types
    final notificationType = data['type'];
    debugPrint("Dashboard: Received notification of type: $notificationType");

    if (notificationType == 'check_out_request_update') {
      // Extract data from notification
      final String status = data['status'] ?? '';
      final String requestType = data['requestType'] ?? 'check-out';
      final String message = data['message'] ?? '';

      // Refresh request history if it's a check-out request update
      if (_isLineManager) {
        _loadPendingApprovalRequests();
      }

      // Show snackbar about request status
      final bool isApproved = status == 'approved';
      CustomSnackBar.successSnackBar(
          isApproved
              ? "Your ${requestType.replaceAll('-', ' ')} request has been approved"
              : "Your ${requestType.replaceAll('-', ' ')} request has been rejected${message.isNotEmpty ? ': $message' : ''}"
      );

      // Refresh in case request status affects current UI
      _refreshDashboard();

    } else if (notificationType == 'new_check_out_request') {
      // Extract data from notification
      final String employeeName = data['employeeName'] ?? 'An employee';
      final String requestType = data['requestType'] ?? 'check-out';

      // Refresh pending requests if it's a new request and user is a manager
      if (_isLineManager) {
        _loadPendingApprovalRequests();

        // Show snackbar about new request
        CustomSnackBar.successSnackBar(
            "$employeeName has requested to ${requestType.replaceAll('-', ' ')} from an offsite location"
        );

        // Navigate to pending requests view if user tapped on notification
        if (data['fromNotificationTap'] == 'true') {
          _navigateToPendingRequests();
        }
      }
    }
  }

  void _navigateToPendingRequests() {
    if (_isLineManager) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ManagerPendingRequestsView(
            managerId: widget.employeeId,
          ),
        ),
      ).then((_) {
        // Refresh the pending count when returning
        _loadPendingApprovalRequests();
      });
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      // Get the notification service from service locator
      final notificationService = getIt<NotificationService>();

      // Register FCM token for this employee
      final fcmTokenService = getIt<FcmTokenService>();
      await fcmTokenService.registerTokenForUser(widget.employeeId);

      // Subscribe to employee-specific notifications
      await notificationService.subscribeToEmployeeTopic(widget.employeeId);

      debugPrint("Dashboard: Initialized notifications for employee ${widget.employeeId}");

      // If user is a line manager, also subscribe to manager notifications
      // This will be done after _fetchUserData() determines if user is a manager
    } catch (e) {
      debugPrint("Dashboard: Error initializing notifications: $e");
    }
  }

// Add this to handle when line manager status is determined
  void _handleLineManagerStatusDetermined(bool isManager) {
    // Called when we determine if user is a line manager
    if (isManager) {
      try {
        final notificationService = getIt<NotificationService>();
        notificationService.subscribeToManagerTopic('manager_${widget.employeeId}');

        // Also try with manager ID without EMP prefix
        if (widget.employeeId.startsWith('EMP')) {
          notificationService.subscribeToManagerTopic('manager_${widget.employeeId.substring(3)}');
        }

        debugPrint("Dashboard: Subscribed to manager notifications");

        // Load pending approval requests
        _loadPendingApprovalRequests();
      } catch (e) {
        debugPrint("Dashboard: Error subscribing to manager notifications: $e");
      }
    }
  }


  Future<void> _loadPendingApprovalRequests() async {
    if (!_isLineManager) return;

    try {
      final repository = getIt<CheckOutRequestRepository>();
      final requests = await repository.getPendingRequestsForManager(widget.employeeId);

      setState(() {
        _pendingApprovalRequests = requests.length;
      });
    } catch (e) {
      debugPrint('Error loading pending approval requests: $e');
    }
  }


  // Add this method to _DashboardViewState class:
  Future<void> _testLineManagerStatus() async {
    debugPrint("=== MANUAL LINE MANAGER TEST ===");

    try {
      // Get all line manager documents
      var snapshot = await FirebaseFirestore.instance
          .collection('line_managers')
          .get();

      debugPrint("Total line manager documents: ${snapshot.docs.length}");

      for (var doc in snapshot.docs) {
        debugPrint("\nDocument ID: ${doc.id}");
        debugPrint("Data: ${doc.data()}");

        Map<String, dynamic> data = doc.data();
        if (data['managerId'] == 'EMP1270') {
          debugPrint("*** FOUND! This is the line manager document for EMP1270 ***");

          setState(() {
            _isLineManager = true;
            _lineManagerDocumentId = doc.id;
            _lineManagerData = data;
          });

          CustomSnackBar.successSnackBar("You are a line manager!");
          return;
        }
      }

      debugPrint("Not found as line manager after checking all documents");
      CustomSnackBar.errorSnackBar("Line manager document not found");

    } catch (e) {
      debugPrint("Error in test: $e");
      CustomSnackBar.errorSnackBar("Error: $e");
    }
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

  // Check if user is within geofence - updated for offline support
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

      // Use the repository instead of the util directly
      List<LocationModel> locations = await _locationRepository.getActiveLocations();

      // Get detailed geofence status with all locations
      Map<String, dynamic> status = await GeofenceUtil.checkGeofenceStatusWithLocations(
          context,
          locations
      );

      bool withinGeofence = status['withinGeofence'] as bool;
      LocationModel? nearestLocation = status['location'] as LocationModel?;
      double? distance = status['distance'] as double?;

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
    setState(() => _isLoading = true);

    try {
      debugPrint("Dashboard loaded with Employee ID: ${widget.employeeId}");

      // First try to get from local storage
      Map<String, dynamic>? localData = await _getUserDataLocally();

      if (localData != null) {
        setState(() {
          _userData = localData;
          // Show local data immediately
          _isLoading = false;
        });

        // If offline, stop here - we've shown cached data
        if (_connectivityService.currentStatus == ConnectionStatus.offline) {
          debugPrint("Using cached user data in offline mode");
          return;
        }
      }

      // If online, try to get fresh data from Firestore
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        DocumentSnapshot snapshot = await FirebaseFirestore.instance
            .collection('employees')
            .doc(widget.employeeId)
            .get();

        if (snapshot.exists) {
          Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

          // Save the data locally for future offline access
          await _saveUserDataLocally(data);

          // Also save the face image separately if it exists
          if (data.containsKey('image') && data['image'] != null) {
            await _saveEmployeeImageLocally(widget.employeeId, data['image']);
          }

          setState(() {
            _userData = data;
            _isLoading = false;
          });

          debugPrint("Updated with fresh data from Firestore");
        } else {
          // Only show this error if we don't have local data already showing
          if (localData == null) {
            setState(() => _isLoading = false);
            CustomSnackBar.errorSnackBar("User data not found");
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");

      // Only update loading state if we don't have local data already showing
      if (_userData == null) {
        setState(() => _isLoading = false);
        CustomSnackBar.errorSnackBar("Error fetching user data: $e");
      }
    }

    // Check if this employee is a line manager - moved outside the first try block
    // In _fetchUserData method, add more debugging
    try {
      // Get the employee's PIN from their data
      String? employeePin = _userData?['pin'] ?? widget.employeeId;

      debugPrint("=== CHECKING LINE MANAGER STATUS ===");
      debugPrint("Current Employee ID: ${widget.employeeId}");
      debugPrint("Employee PIN: $employeePin");
      debugPrint("User Data available: ${_userData != null}");

      // Check if this employee is a line manager by looking through all line_managers documents
      bool isLineManager = false;
      Map<String, dynamic>? foundLineManagerData;
      String? lineManagerDocId;

      // Get all line manager documents
      var lineManagersSnapshot = await FirebaseFirestore.instance
          .collection('line_managers')
          .get();

      debugPrint("Found ${lineManagersSnapshot.docs.length} line manager documents");

      for (var doc in lineManagersSnapshot.docs) {
        Map<String, dynamic> data = doc.data();
        String managerId = data['managerId'] ?? '';

        debugPrint("Checking line manager doc ${doc.id}: managerId = $managerId");

        // Check if this employee matches the managerId in various formats
        if (managerId == widget.employeeId ||
            managerId == 'EMP${widget.employeeId}' ||
            managerId == 'EMP$employeePin' ||
            (employeePin != null && managerId == employeePin)) {
          isLineManager = true;
          lineManagerDocId = doc.id;
          foundLineManagerData = data;
          debugPrint("✓ Found match! Employee is a line manager");
          break;
        }
      }

      // Store the results
      setState(() {
        _isLineManager = isLineManager;
        _lineManagerDocumentId = lineManagerDocId;
        _lineManagerData = foundLineManagerData;
      });
      _handleLineManagerStatusDetermined(_isLineManager);

      debugPrint("=== LINE MANAGER CHECK COMPLETE ===");
      debugPrint("Is Line Manager: $_isLineManager");
      if (_isLineManager && _lineManagerData != null) {
        debugPrint("Line Manager Document ID: $_lineManagerDocumentId");
        debugPrint("Line Manager Data: $_lineManagerData");
        debugPrint("Manager ID: ${_lineManagerData!['managerId']}");
        debugPrint("Team Members: ${_lineManagerData!['teamMembers']}");
      }
      debugPrint("===================================");

    } catch (e) {
      debugPrint("ERROR checking line manager status: $e");
      setState(() {
        _isLineManager = false;
        _lineManagerData = null;
      });
    }
  }

  // Save user data locally
  Future<void> _saveUserDataLocally(Map<String, dynamic> userData) async {
    try {
      // Create a deep copy of the data that we can modify
      Map<String, dynamic> dataCopy = Map<String, dynamic>.from(userData);

      // Convert all Timestamp objects to ISO8601 strings
      dataCopy.forEach((key, value) {
        if (value is Timestamp) {
          dataCopy[key] = value.toDate().toIso8601String();
        }
      });

      // Now save the converted data
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_data_${widget.employeeId}', jsonEncode(dataCopy));
      await prefs.setString('user_name_${widget.employeeId}', userData['name'] ?? '');

      debugPrint("User data saved locally for ID: ${widget.employeeId}");
    } catch (e) {
      debugPrint('Error saving user data locally: $e');
    }
  }

  // Save comprehensive employee data for offline auth
  Future<void> _saveEmployeeDataLocally(String employeeId, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save the complete image string
      if (data.containsKey('image') && data['image'] != null) {
        await prefs.setString('employee_image_$employeeId', data['image']);
        debugPrint("Saved employee image locally for ID: $employeeId");
      }

      // Save facial features specifically for authentication
      if (data.containsKey('faceFeatures') && data['faceFeatures'] != null) {
        await prefs.setString('employee_face_features_$employeeId',
            jsonEncode(data['faceFeatures']));
        debugPrint("Saved facial features locally for ID: $employeeId");
      }

      // Save the complete user data
      await prefs.setString('user_data_$employeeId', jsonEncode(data));

      debugPrint("Saved comprehensive user data locally for ID: $employeeId");
    } catch (e) {
      debugPrint('Error saving employee data locally: $e');
    }
  }

  // Save employee image locally for offline face verification
  Future<void> _saveEmployeeImageLocally(String employeeId, String imageBase64) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('employee_image_$employeeId', imageBase64);
      debugPrint("Employee image saved locally for ID: $employeeId");
    } catch (e) {
      debugPrint("Error saving employee image locally: $e");
    }
  }

  // Get user data from local storage
  Future<Map<String, dynamic>?> _getUserDataLocally() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userData = prefs.getString('user_data_${widget.employeeId}');

      if (userData != null) {
        Map<String, dynamic> data = jsonDecode(userData) as Map<String, dynamic>;
        debugPrint("Retrieved complete user data from local storage");
        return data;
      }

      // Fallback to individual fields
      String? userName = prefs.getString('user_name_${widget.employeeId}');
      if (userName != null && userName.isNotEmpty) {
        return {'name': userName};
      }

      debugPrint("No local user data found for ID: ${widget.employeeId}");
      return null;
    } catch (e) {
      debugPrint('Error getting user data locally: $e');
      return null;
    }
  }

  Future<void> _fetchAttendanceStatus() async {
    try {
      // Get today's date in YYYY-MM-DD format for the document ID
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Always check local database first
      final localAttendance = await _attendanceRepository.getTodaysAttendance(widget.employeeId);

      if (localAttendance != null) {
        setState(() {
          _isCheckedIn = localAttendance.checkIn != null && localAttendance.checkOut == null;
          if (_isCheckedIn && localAttendance.checkIn != null) {
            _checkInTime = DateTime.parse(localAttendance.checkIn!);
          } else {
            _checkInTime = null;
          }
        });

        debugPrint("Loaded attendance from local database: CheckedIn=$_isCheckedIn");
      }

      // If online, try to get fresh data from Firestore as well (which might be more up-to-date)
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        try {
          DocumentSnapshot attendanceDoc = await FirebaseFirestore.instance
              .collection('employees')
              .doc(widget.employeeId)
              .collection('attendance')
              .doc(today)
              .get()
              .timeout(const Duration(seconds: 5));

          if (attendanceDoc.exists) {
            Map<String, dynamic> data = attendanceDoc.data() as Map<String, dynamic>;

            // Update local state with fresh data
            setState(() {
              _isCheckedIn = data['checkIn'] != null && data['checkOut'] == null;
              if (_isCheckedIn && data['checkIn'] != null) {
                _checkInTime = (data['checkIn'] as Timestamp).toDate();
              } else {
                _checkInTime = null;
              }
            });

            // Cache the attendance status
            await _saveAttendanceStatusLocally(today, data);
            debugPrint("Fetched and cached fresh attendance status from Firestore");
          }
        } catch (e) {
          debugPrint("Network error fetching attendance status: $e");
          // Continue with local data if network fails
        }
      }
    } catch (e) {
      debugPrint("Error fetching attendance: $e");
      // Fall back to simple state
      setState(() {
        _isCheckedIn = false;
        _checkInTime = null;
      });
    }
  }

  Future<void> _testOfflineAuthentication() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedImage = prefs.getString('employee_image_${widget.employeeId}');

      if (storedImage == null || storedImage.isEmpty) {
        CustomSnackBar.errorSnackBar("No stored face image found");
        return;
      }

      // Check if image is in data URL format and fix it
      String cleanedImage = storedImage;
      bool wasFixed = false;

      if (cleanedImage.contains('data:image') && cleanedImage.contains(',')) {
        cleanedImage = cleanedImage.split(',')[1];
        wasFixed = true;
      }

      // Save the fixed image if needed
      if (wasFixed) {
        await prefs.setString('employee_image_${widget.employeeId}', cleanedImage);
        CustomSnackBar.successSnackBar("Fixed image format! Try authentication now");
      } else {
        CustomSnackBar.successSnackBar("Image format looks good! Length: ${cleanedImage.length}");
      }
    } catch (e) {
      CustomSnackBar.errorSnackBar("Error: $e");
    }
  }


  Future<void> _testNotification() async {
    try {
      final notificationService = getIt<NotificationService>();

      // Show a dialog with options
      final notificationType = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Test Notification Type'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'check-in'),
              child: const Text('New Check-In Request'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'check-out'),
              child: const Text('New Check-Out Request'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'approved'),
              child: const Text('Request Approved'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'rejected'),
              child: const Text('Request Rejected'),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'local'),
              child: const Text('Local Notification (no Firebase)'),
            ),
          ],
        ),
      );

      if (notificationType == null) return;

      if (notificationType == 'local') {
        // Send a local notification for testing
        await notificationService.sendTestNotification(
            'Test Notification',
            'This is a test notification sent locally'
        );
        CustomSnackBar.successSnackBar("Local test notification sent");
        return;
      }

      // Send a cloud message based on selected type
      Map<String, dynamic> notificationData = {
        'employeeId': widget.employeeId,
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      };

      String title, body;

      switch (notificationType) {
        case 'check-in':
          title = 'New Check-In Request';
          body = 'An employee has requested to check in from an offsite location';
          notificationData['type'] = 'new_check_out_request';
          notificationData['requestType'] = 'check-in';
          break;
        case 'check-out':
          title = 'New Check-Out Request';
          body = 'An employee has requested to check out from an offsite location';
          notificationData['type'] = 'new_check_out_request';
          notificationData['requestType'] = 'check-out';
          break;
        case 'approved':
          title = 'Request Approved';
          body = 'Your check-in request has been approved';
          notificationData['type'] = 'check_out_request_update';
          notificationData['status'] = 'approved';
          notificationData['requestType'] = 'check-in';
          break;
        case 'rejected':
          title = 'Request Rejected';
          body = 'Your check-out request has been rejected';
          notificationData['type'] = 'check_out_request_update';
          notificationData['status'] = 'rejected';
          notificationData['requestType'] = 'check-out';
          notificationData['message'] = 'Not approved at this time';
          break;
        default:
          title = 'Test Notification';
          body = 'This is a test notification';
          notificationData['type'] = 'test';
      }

      // Add a test notification to Cloud Firestore
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('fcm_token');

      if (token == null) {
        CustomSnackBar.errorSnackBar("No FCM token found");
        return;
      }

      await FirebaseFirestore.instance.collection('notifications').add({
        'token': token,
        'title': title,
        'body': body,
        'data': notificationData,
        'sentAt': FieldValue.serverTimestamp(),
      });

      CustomSnackBar.successSnackBar("Test notification sent to Firebase");
    } catch (e) {
      debugPrint("Error sending test notification: $e");
      CustomSnackBar.errorSnackBar("Error sending test notification: $e");
    }
  }

  // Save attendance status locally
  Future<void> _saveAttendanceStatusLocally(String date, Map<String, dynamic> data) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      // Convert Timestamp to ISO string for storage
      if (data['checkIn'] != null && data['checkIn'] is Timestamp) {
        data['checkIn'] = (data['checkIn'] as Timestamp).toDate().toIso8601String();
      }
      if (data['checkOut'] != null && data['checkOut'] is Timestamp) {
        data['checkOut'] = (data['checkOut'] as Timestamp).toDate().toIso8601String();
      }
      await prefs.setString('attendance_${widget.employeeId}_$date', jsonEncode(data));
      debugPrint("Attendance status saved locally for date: $date");
    } catch (e) {
      debugPrint('Error saving attendance status locally: $e');
    }
  }

  // Get attendance status from local storage
  Future<Map<String, dynamic>?> _getAttendanceStatusLocally(String date) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      String? attendanceData = prefs.getString('attendance_${widget.employeeId}_$date');
      if (attendanceData != null) {
        debugPrint("Retrieved attendance status from local storage for date: $date");
        return jsonDecode(attendanceData) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error getting attendance status locally: $e');
    }
    return null;
  }

  // Clear attendance status from local storage
  Future<void> _clearAttendanceStatusLocally(String date) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('attendance_${widget.employeeId}_$date');
      debugPrint("Cleared attendance status from local storage for date: $date");
    } catch (e) {
      debugPrint('Error clearing attendance status locally: $e');
    }
  }

  Future<void> _fetchRecentActivity() async {
    try {
      List<Map<String, dynamic>> activity = [];

      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        // Online mode - fetch from Firestore
        final QuerySnapshot snapshot = await FirebaseFirestore.instance
            .collection('employees')
            .doc(widget.employeeId)
            .collection('attendance')
            .orderBy('date', descending: true)
            .limit(5)
            .get();

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

        // Cache recent activity
        await _saveRecentActivityLocally(activity);
        debugPrint("Fetched and cached recent activity");
      } else {
        // Offline mode - get from local storage
        activity = await _getRecentActivityLocally() ?? [];
        debugPrint("Using cached recent activity in offline mode");

        // If no cached data, try to get from local database
        if (activity.isEmpty) {
          final localRecords = await _attendanceRepository.getRecentAttendance(widget.employeeId, 5);
          for (var record in localRecords) {
            activity.add(record.rawData);
          }
          debugPrint("Retrieved ${activity.length} records from local database");
        }
      }

      setState(() {
        _recentActivity = activity;
      });
    } catch (e) {
      debugPrint("Error fetching activity: $e");

      // Try to get from local storage as fallback
      final cachedActivity = await _getRecentActivityLocally();
      if (cachedActivity != null && cachedActivity.isNotEmpty) {
        setState(() {
          _recentActivity = cachedActivity;
        });
        debugPrint("Using cached activity after error");
      }
    }
  }

  // Save recent activity locally
  Future<void> _saveRecentActivityLocally(List<Map<String, dynamic>> activity) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // Process timestamps to ISO strings for storage
      final processedActivity = activity.map((item) {
        final processedItem = Map<String, dynamic>.from(item);
        if (processedItem['checkIn'] != null && processedItem['checkIn'] is Timestamp) {
          processedItem['checkIn'] = (processedItem['checkIn'] as Timestamp).toDate().toIso8601String();
        }
        if (processedItem['checkOut'] != null && processedItem['checkOut'] is Timestamp) {
          processedItem['checkOut'] = (processedItem['checkOut'] as Timestamp).toDate().toIso8601String();
        }
        return processedItem;
      }).toList();

      await prefs.setString('recent_activity_${widget.employeeId}', jsonEncode(processedActivity));
      debugPrint("Recent activity saved locally");
    } catch (e) {
      debugPrint('Error saving recent activity locally: $e');
    }
  }

  // Get recent activity from local storage
  Future<List<Map<String, dynamic>>?> _getRecentActivityLocally() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      String? activityData = prefs.getString('recent_activity_${widget.employeeId}');
      if (activityData != null) {
        debugPrint("Retrieved recent activity from local storage");
        final List<dynamic> decoded = jsonDecode(activityData);
        return decoded.map((item) => item as Map<String, dynamic>).toList();
      }
    } catch (e) {
      debugPrint('Error getting recent activity locally: $e');
    }
    return null;
  }

  // Updates to the _handleCheckInOut method in dashboard_view.dart

  Future<void> _handleCheckInOut() async {
    // If already in authentication process, prevent multiple taps
    if (_isAuthenticating) {
      return;
    }

    // First, refresh the geofence status
    await _checkGeofenceStatus();

    if (!_isCheckedIn) {
      // ===== CHECK-IN FLOW =====
      // Set authenticating flag
      setState(() {
        _isAuthenticating = true;
      });

      // Launch face authentication dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return WillPopScope(
            onWillPop: () async => false,
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
                      // Get current position
                      Position? currentPosition = await GeofenceUtil.getCurrentPosition();

                      // If authentication successful, handle check-in with geofence
                      await CheckInOutHandler.handleOffLocationAction(
                        context: context,
                        employeeId: widget.employeeId,
                        employeeName: _userData?['name'] ?? 'Employee',
                        isWithinGeofence: _isWithinGeofence,
                        currentPosition: currentPosition,
                        isCheckIn: true, // This is check-in
                        onRegularAction: () async {
                          // Regular check-in process when within geofence
                          bool checkInSuccess = await _attendanceRepository.recordCheckIn(
                            employeeId: widget.employeeId,
                            checkInTime: DateTime.now(),
                            locationId: _nearestLocation?.id ?? 'default',
                            locationName: _nearestLocation?.name ?? 'Unknown',
                            locationLat: currentPosition?.latitude ?? _nearestLocation!.latitude,
                            locationLng: currentPosition?.longitude ?? _nearestLocation!.longitude,
                          );

                          if (checkInSuccess) {
                            setState(() {
                              _isCheckedIn = true;
                              _checkInTime = DateTime.now();

                              // If offline, mark that we need to sync later
                              if (_connectivityService.currentStatus == ConnectionStatus.offline) {
                                _needsSync = true;
                              }
                            });

                            CustomSnackBar.successSnackBar("Checked in successfully at $_currentTime");

                            // Refresh activity list
                            _fetchRecentActivity();
                          } else {
                            CustomSnackBar.errorSnackBar("Failed to record check-in. Please try again.");
                          }
                        },
                      );
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
      // ===== CHECK-OUT FLOW =====
      setState(() {
        _isAuthenticating = true;
      });

      // Get current position
      Position? currentPosition = await GeofenceUtil.getCurrentPosition();

      // First, use the face authentication
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
                      // Ensure we have the most up-to-date status before processing checkout
                      await _ensureFreshAttendanceStatus();

                      // Double check we're still checked in before proceeding
                      if (!_isCheckedIn) {
                        CustomSnackBar.errorSnackBar("You are not currently checked in");
                        return;
                      }

                      // If face auth successful, handle check-out with geofence
                      await CheckInOutHandler.handleOffLocationAction(
                        context: context,
                        employeeId: widget.employeeId,
                        employeeName: _userData?['name'] ?? 'Employee',
                        isWithinGeofence: _isWithinGeofence,
                        currentPosition: currentPosition,
                        isCheckIn: false, // This is check-out
                        onRegularAction: () async {
                          // Proceed with regular check-out process
                          bool checkOutSuccess = await _attendanceRepository.recordCheckOut(
                            employeeId: widget.employeeId,
                            checkOutTime: DateTime.now(),
                          );

                          if (checkOutSuccess) {
                            // Update state to reflect check-out
                            setState(() {
                              _isCheckedIn = false;
                              _checkInTime = null;

                              // If offline, mark that we need to sync later
                              if (_connectivityService.currentStatus == ConnectionStatus.offline) {
                                _needsSync = true;
                              }
                            });

                            CustomSnackBar.successSnackBar("Checked out successfully at $_currentTime");

                            // Refresh activity list and attendance status
                            await _fetchAttendanceStatus();
                            await _fetchRecentActivity();
                          } else {
                            CustomSnackBar.errorSnackBar("Failed to record check-out. Please try again.");
                          }
                        },
                      );
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

  // Add the refresh dashboard method
  Future<void> _refreshDashboard() async {
    await _fetchUserData();
    await _fetchAttendanceStatus();
    await _fetchRecentActivity();
    await _checkGeofenceStatus();

    // Check if we need to sync
    if (_connectivityService.currentStatus == ConnectionStatus.online) {
      final pendingRecords = await _attendanceRepository.getPendingRecords();
      setState(() {
        _needsSync = pendingRecords.isNotEmpty;

      });
    }
    if (_isLineManager) {
      await _loadPendingApprovalRequests();
    }
  }

  // Add the ensure fresh attendance status method
  // Add the ensure fresh attendance status method
  Future<void> _ensureFreshAttendanceStatus() async {
    String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Always check local database first
    final localAttendance = await _attendanceRepository.getTodaysAttendance(widget.employeeId);

    if (localAttendance != null) {
      bool hasCheckedIn = localAttendance.checkIn != null;
      bool hasCheckedOut = localAttendance.checkOut != null;

      setState(() {
        _isCheckedIn = hasCheckedIn && !hasCheckedOut;
        if (_isCheckedIn && localAttendance.checkIn != null) {
          _checkInTime = DateTime.parse(localAttendance.checkIn!);
        } else {
          _checkInTime = null;
        }
      });

      debugPrint("Fresh attendance status - CheckedIn: $_isCheckedIn, HasCheckedOut: $hasCheckedOut");
    } else {
      // Only if we have no local data at all
      setState(() {
        _isCheckedIn = false;
        _checkInTime = null;
      });
      debugPrint("No local attendance record found for today");
    }
  }

  // Manual sync trigger for UI
  Future<void> _manualSync() async {
    if (_connectivityService.currentStatus == ConnectionStatus.offline) {
      CustomSnackBar.errorSnackBar("Cannot sync while offline. Please check your connection.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _syncService.manualSync();

      // Refresh all data after sync
      await _fetchUserData();
      await _fetchAttendanceStatus();
      await _fetchRecentActivity();

      setState(() {
        _needsSync = false;
        _isLoading = false;
      });

      CustomSnackBar.successSnackBar("Data synchronized successfully");
    } catch (e) {
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar("Error during sync: $e");
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
        // If we have pending syncs, prompt to sync first
        if (_needsSync && _connectivityService.currentStatus == ConnectionStatus.online) {
          bool syncFirst = await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Unsynchronized Data"),
              content: const Text("You have data that hasn't been synchronized. Would you like to sync before logging out?"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text("No"),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text("Yes"),
                ),
              ],
            ),
          ) ?? false;

          if (syncFirst) {
            await _manualSync();
          }
        }

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
          : Column(
        children: [
          // Add connectivity banner at the top
          ConnectivityBanner(connectivityService: _connectivityService),

          // Add sync status banner if needed
          if (_needsSync && _connectivityService.currentStatus == ConnectionStatus.online)
            GestureDetector(
              onTap: _manualSync,
              child: Container(
                color: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.sync, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Tap to synchronize pending data',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          Expanded(
            child: SafeArea(
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
          ),
        ],
      ),
      // Add floating action button to refresh geofence status
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Add sync button if we have pending data to sync
          if (_needsSync && _connectivityService.currentStatus == ConnectionStatus.online)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FloatingActionButton(
                onPressed: _manualSync,
                tooltip: 'Sync Data',
                backgroundColor: Colors.orange,
                heroTag: 'syncButton',
                child: const Icon(Icons.sync),
              ),
            ),

          // Regular location refresh button
          FloatingActionButton(
            onPressed: _checkGeofenceStatus,
            tooltip: 'Refresh Location',
            backgroundColor: accentColor,
            heroTag: 'locationButton',
            child: const Icon(Icons.refresh_rounded),
          ),
        ],
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
          // Status information - Fixed overflow issue
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left side - Status text
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
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
                    ),

                    // Status indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _isCheckedIn
                            ? Colors.green.withOpacity(0.3)
                            : Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
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
              ],
            ),
          ),

          // Offline test button - moved to separate row to prevent overflow
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.bug_report),
              label: const Text("OFFLINE AUTH TEST"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              ),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => OfflineTestView(
                      employeeId: widget.employeeId,
                    ),
                  ),
                );
              },
            ),
          ),

          // Offline badge if record hasn't been synced
          if (_needsSync && _isCheckedIn)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync_disabled, color: Colors.orange, size: 14),
                    SizedBox(width: 4),
                    Text(
                      "Pending sync",
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          // Connection status indicator
          if (_connectivityService.currentStatus == ConnectionStatus.offline)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.wifi_off, color: Colors.red, size: 14),
                    SizedBox(width: 4),
                    Text(
                      "Offline Mode - Using cached data",
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                ),
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
              // Add a button to sync data if we're offline and have data to sync
              if (_needsSync && _connectivityService.currentStatus == ConnectionStatus.online)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ElevatedButton.icon(
                    onPressed: _manualSync,
                    icon: const Icon(Icons.sync),
                    label: const Text("Sync Data"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
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

          // Handle both Timestamp and String (from cache) formats for checkIn/checkOut
          DateTime? checkIn;
          if (activity['checkIn'] != null) {
            if (activity['checkIn'] is Timestamp) {
              checkIn = (activity['checkIn'] as Timestamp).toDate();
            } else if (activity['checkIn'] is String) {
              checkIn = DateTime.parse(activity['checkIn']);
            }
          }

          DateTime? checkOut;
          if (activity['checkOut'] != null) {
            if (activity['checkOut'] is Timestamp) {
              checkOut = (activity['checkOut'] as Timestamp).toDate();
            } else if (activity['checkOut'] is String) {
              checkOut = DateTime.parse(activity['checkOut']);
            }
          }

          String status = activity['workStatus'] ?? 'Unknown';
          String location = activity['location'] ?? 'Unknown';

          // Add sync status indicator for records that are not synced
          bool isSynced = activity['isSynced'] ?? true;

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
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      _formatDisplayDate(date),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: _isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  // Show sync indicator if needed
                  if (!isSynced)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.sync_disabled, color: Colors.orange, size: 12),
                          SizedBox(width: 4),
                          Text(
                            "Pending",
                            style: TextStyle(color: Colors.orange, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                ],
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

  // Debug version of _buildMenuTab to see what's happening

  Widget _buildMenuTab() {
    debugPrint("Building menu tab. Is Line Manager: $_isLineManager");

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

          if (_isLineManager) ...[
            _buildMenuOption(
              icon: Icons.people_outline,
              title: 'My Team',
              subtitle: 'View team members and attendance',
              onTap: () {
                debugPrint("=== MY TEAM BUTTON CLICKED ===");
                debugPrint("Line Manager Data exists: ${_lineManagerData != null}");

                if (_lineManagerData != null) {
                  debugPrint("Manager Data: $_lineManagerData");

                  String managerId = _lineManagerData!['managerId'] ?? '';
                  debugPrint("Manager ID to pass: $managerId");

                  if (managerId.isNotEmpty) {
                    debugPrint("Navigating to TeamManagementView with managerId: $managerId");

                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => TeamManagementView(
                          managerId: managerId,
                          managerData: _userData!,
                        ),
                      ),
                    ).then((value) {
                      debugPrint("Returned from TeamManagementView");
                    }).catchError((error) {
                      debugPrint("Navigation error: $error");
                    });
                  } else {
                    debugPrint("Manager ID is empty!");
                    CustomSnackBar.errorSnackBar("Manager ID not found");
                  }
                } else {
                  debugPrint("Line Manager Data is null!");
                  CustomSnackBar.errorSnackBar("Line manager data not available");
                }

                debugPrint("=========================");
              },
            ),

            // Add the pending approval requests option with a badge
            _buildMenuOption(
              icon: Icons.approval,
              title: 'Pending Approval Requests',
              subtitle: _pendingApprovalRequests > 0
                  ? '$_pendingApprovalRequests requests waiting for your approval'
                  : 'No pending requests',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ManagerPendingRequestsView(
                      managerId: widget.employeeId,
                    ),
                  ),
                ).then((_) {
                  // Refresh the pending count when returning
                  _loadPendingApprovalRequests();
                });
              },
              showStatusIcon: _pendingApprovalRequests > 0,
              statusIcon: Icons.notifications_active,
              statusColor: Colors.orange,
              showBadge: _pendingApprovalRequests > 0,
              badgeCount: _pendingApprovalRequests,
            ),
          ],


          // Debug menu option when not a line manager
          if (!_isLineManager)
            _buildMenuOption(
              icon: Icons.info_outline,
              title: 'Debug: Not a Line Manager',
              subtitle: 'Employee ID: ${widget.employeeId}',
              onTap: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Debug Info'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Employee ID: ${widget.employeeId}'),
                        Text('Is Line Manager: $_isLineManager'),
                        Text('User Data Available: ${_userData != null}'),
                        if (_userData != null) ...[
                          Text('Name: ${_userData!['name'] ?? 'N/A'}'),
                          Text('PIN: ${_userData!['pin'] ?? 'N/A'}'),
                        ],
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Debug force check button
          _buildMenuOption(
            icon: Icons.bug_report,
            title: 'Force Check Line Manager',
            subtitle: 'Debug tool',
            onTap: () async {
              debugPrint("=== FORCE CHECK LINE MANAGER ===");
              debugPrint("Current Employee ID: ${widget.employeeId}");
              debugPrint("Current Line Manager Status: $_isLineManager");

              try {
                // Check all possible formats
                List<String> possibleIds = [
                  widget.employeeId,
                  'EMP${widget.employeeId}',
                  'EMP${_userData?['pin'] ?? ''}',
                  _userData?['pin'] ?? '',
                ];

                for (String id in possibleIds) {
                  debugPrint("Checking format: $id");
                  var query = await FirebaseFirestore.instance
                      .collection('line_managers')
                      .where('managerId', isEqualTo: id)
                      .get();

                  if (query.docs.isNotEmpty) {
                    debugPrint("FOUND! Line manager with ID: $id");
                    debugPrint("Document data: ${query.docs.first.data()}");

                    setState(() {
                      _isLineManager = true;
                    });

                    CustomSnackBar.successSnackBar("You are a line manager!");
                    return;
                  }
                }

                debugPrint("NOT FOUND as line manager with any format");
                CustomSnackBar.errorSnackBar("Not found as line manager");

              } catch (e) {
                debugPrint("Error: $e");
                CustomSnackBar.errorSnackBar("Error: $e");
              }
            },
          ),

          if (kDebugMode)
            _buildMenuOption(
              icon: Icons.notifications,
              title: 'Test Notifications',
              subtitle: 'Send a test push notification',
              onTap: _testNotification,
              showStatusIcon: true,
              statusIcon: Icons.send,
              statusColor: Colors.orange,
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

          // Add sync option for offline data
          if (_needsSync)
            _buildMenuOption(
              icon: Icons.sync,
              title: 'Sync Data',
              subtitle: _connectivityService.currentStatus == ConnectionStatus.online
                  ? 'You have pending data to synchronize'
                  : 'Connect to network to sync data',
              onTap: _connectivityService.currentStatus == ConnectionStatus.online
                  ? _manualSync
                  : null,
              showStatusIcon: true,
              statusIcon: _connectivityService.currentStatus == ConnectionStatus.online
                  ? Icons.cloud_upload
                  : Icons.cloud_off,
              statusColor: _connectivityService.currentStatus == ConnectionStatus.online
                  ? Colors.orange
                  : Colors.grey,
            ),

          _buildMenuOption(
            icon: Icons.settings_outlined,
            title: 'Settings',
            onTap: () {
              _showComingSoonDialog('Settings');
            },
          ),

          _buildMenuOption(
            icon: Icons.history,
            title: 'Check-Out Request History',
            subtitle: 'View your remote check-out requests',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => CheckOutRequestHistoryView(
                    employeeId: widget.employeeId,
                  ),
                ),
              );
            },
          ),

          // Connection status option
          _buildMenuOption(
            icon: _connectivityService.currentStatus == ConnectionStatus.online
                ? Icons.wifi
                : Icons.wifi_off,
            title: 'Connection Status',
            subtitle: _connectivityService.currentStatus == ConnectionStatus.online
                ? 'Online mode'
                : 'Offline mode',
            textColor: _connectivityService.currentStatus == ConnectionStatus.online
                ? Colors.green
                : Colors.orange,
            iconColor: _connectivityService.currentStatus == ConnectionStatus.online
                ? Colors.green
                : Colors.orange,
            onTap: null, // Just informational, no action
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
    bool showBadge = false,
    int badgeCount = 0,
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
                child: Stack(
                  children: [
                    Icon(
                      icon,
                      color: iconColor,
                      size: 22,
                    ),
                    if (showBadge && badgeCount > 0)
                      Positioned(
                        right: -3,
                        top: -3,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            badgeCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
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
              else if (!showStatusIcon && onTap != null)
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

// Helper extension method for GeofenceUtil to use location list
extension GeofenceUtilExtension on GeofenceUtil {
  static Future<Map<String, dynamic>> checkGeofenceStatusWithLocations(
      BuildContext context,
      List<LocationModel> locations
      ) async {
    bool hasPermission = await GeofenceUtil.checkLocationPermission(context);
    if (!hasPermission) {
      return {
        'withinGeofence': false,
        'location': null,
        'distance': null,
      };
    }

    Position? currentPosition = await GeofenceUtil.getCurrentPosition();
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to get current location'),
          backgroundColor: Colors.red,
        ),
      );
      return {
        'withinGeofence': false,
        'location': null,
        'distance': null,
      };
    }

    // Find closest location and check if within radius
    LocationModel? closestLocation;
    double? shortestDistance;
    bool withinAnyGeofence = false;

    for (var location in locations) {
      double distanceInMeters = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        location.latitude,
        location.longitude,
      );

      // Update closest location if this is closer than previous
      if (shortestDistance == null || distanceInMeters < shortestDistance) {
        shortestDistance = distanceInMeters;
        closestLocation = location;
      }

      // Check if within this location's radius
      if (distanceInMeters <= location.radius) {
        withinAnyGeofence = true;
        // If within radius, prioritize this location
        closestLocation = location;
        shortestDistance = distanceInMeters;
        break; // Optimization: we found a matching location, no need to check others
      }
    }

    // Return result
    return {
      'withinGeofence': withinAnyGeofence,
      'location': closestLocation,
      'distance': shortestDistance,
    };
  }
}

// Add the AppLifecycleObserver class
class AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback? onResume;

  AppLifecycleObserver({this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && onResume != null) {
      onResume!();
    }
  }
}