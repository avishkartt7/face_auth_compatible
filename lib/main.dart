// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/onboarding/onboarding_screen.dart';
import 'package:face_auth_compatible/pin_entry/pin_entry_view.dart';
import 'package:face_auth_compatible/pin_entry/app_password_entry_view.dart';
import 'package:face_auth_compatible/dashboard/dashboard_view.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:face_auth_compatible/services/service_locator.dart';

// Import the new services for offline functionality
import 'package:face_auth_compatible/services/sync_service.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Initialize Firestore for offline persistence
  await _initializeFirestoreOfflineMode();

  // Setup service locator
  setupServiceLocator();

  runApp(const MyApp());
}

// Configure Firestore for offline persistence
Future<void> _initializeFirestoreOfflineMode() async {
  FirebaseFirestore.instance.settings = Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool? _showOnboarding;
  String? _loggedInEmployeeId;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _initializeLocationData();
    _initializeAdminAccount();
  }

  Future<void> _checkLoginStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool onboardingComplete = prefs.getBool('onboardingComplete') ?? false;
    String? authenticatedUserId = prefs.getString('authenticated_user_id');

    if (!onboardingComplete) {
      setState(() {
        _showOnboarding = true;
      });
      return;
    }

    // Check if a user is already authenticated (has an app password)
    if (authenticatedUserId != null) {
      // First check locally stored data
      bool userExists = await _checkUserExistsLocally(authenticatedUserId);

      if (userExists) {
        setState(() {
          _loggedInEmployeeId = authenticatedUserId;
          _showOnboarding = false;
        });
        return;
      }

      // If not found locally or online mode, check Firestore
      if (getIt<ConnectivityService>().currentStatus == ConnectionStatus.online) {
        try {
          DocumentSnapshot doc = await FirebaseFirestore.instance
              .collection('employees')
              .doc(authenticatedUserId)
              .get();

          if (doc.exists) {
            // Cache the user data locally
            _saveUserDataLocally(authenticatedUserId, doc.data() as Map<String, dynamic>);

            setState(() {
              _loggedInEmployeeId = authenticatedUserId;
              _showOnboarding = false;
            });
            return;
          }
        } catch (e) {
          print("Error checking authenticated user: $e");
        }
      }
    }

    // Check if any user is registered - locally first if offline
    if (getIt<ConnectivityService>().currentStatus == ConnectionStatus.offline) {
      bool hasRegisteredUsers = await _checkRegisteredUsersLocally();
      setState(() {
        _showOnboarding = !hasRegisteredUsers;
      });
      return;
    }

    // If online, check Firestore
    try {
      QuerySnapshot userQuery = await FirebaseFirestore.instance
          .collection('employees')
          .where('registrationCompleted', isEqualTo: true)
          .limit(1)
          .get();

      setState(() {
        // If users exist, show app password entry, otherwise show PIN entry
        _showOnboarding = userQuery.docs.isEmpty;
      });
    } catch (e) {
      print("Error checking registration status: $e");
      // Default to onboarding if error
      setState(() {
        _showOnboarding = true;
      });
    }
  }

  // Check if user exists in local storage
  Future<bool> _checkUserExistsLocally(String userId) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      return prefs.containsKey('user_data_$userId');
    } catch (e) {
      print("Error checking local user data: $e");
      return false;
    }
  }

  // Save user data locally
  Future<void> _saveUserDataLocally(String userId, Map<String, dynamic> userData) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // Store the full data
      await prefs.setString('user_data_$userId', jsonEncode(userData));

      // Store critical fields separately for redundancy
      await prefs.setString('user_name_$userId', userData['name'] ?? '');
      await prefs.setString('user_designation_$userId', userData['designation'] ?? '');

      debugPrint("User data saved locally for ID: $userId");
    } catch (e) {
      debugPrint('Error saving user data locally: $e');
    }
  }

  // Check if there are any registered users locally
  Future<bool> _checkRegisteredUsersLocally() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      // Get all keys that might be user data
      Set<String> keys = prefs.getKeys();
      return keys.any((key) => key.startsWith('user_exists_'));
    } catch (e) {
      print("Error checking registered users locally: $e");
      return false;
    }
  }

  Future<void> _initializeLocationData() async {
    // Only run this if online
    if (getIt<ConnectivityService>().currentStatus == ConnectionStatus.offline) {
      return;
    }

    try {
      // Check if we need to create the default location
      QuerySnapshot locationsSnapshot = await FirebaseFirestore.instance
          .collection('locations')
          .limit(1)
          .get();

      if (locationsSnapshot.docs.isEmpty) {
        // No locations exist, create the default one
        await FirebaseFirestore.instance.collection('locations').add({
          'name': 'Central Plaza',
          'address': 'DIP 1, Street 72, Dubai',
          'latitude': 24.985454,
          'longitude': 55.175509,
          'radius': 200.0,
          'isActive': true,
        });

        print('Default location created');
      }
    } catch (e) {
      print('Error initializing location data: $e');
    }
  }

  Future<void> _initializeAdminAccount() async {
    // Only run this if online
    if (getIt<ConnectivityService>().currentStatus == ConnectionStatus.offline) {
      return;
    }

    try {
      // Check if admin users collection exists
      final adminSnapshot = await FirebaseFirestore.instance
          .collection('admins')
          .limit(1)
          .get();

      if (adminSnapshot.docs.isEmpty) {
        // Create default admin account with credentials from your request
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: "admin@pts",
          password: "pts123",
        ).then((userCredential) async {
          // Store admin role in Firestore
          await FirebaseFirestore.instance
              .collection('admins')
              .doc(userCredential.user!.uid)
              .set({
            'email': "admin@pts",
            'isAdmin': true,
            'createdAt': FieldValue.serverTimestamp(),
          });

          print('Default admin account created');
        });
      }
    } catch (e) {
      print('Error creating admin account: $e');
      // Likely already exists, just continue
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PHOENICIAN',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSwatch(accentColor: accentColor),
        inputDecorationTheme: InputDecorationTheme(
          contentPadding: const EdgeInsets.all(20),
          filled: true,
          fillColor: primaryWhite,
          hintStyle: TextStyle(
            color: primaryBlack.withOpacity(0.6),
            fontWeight: FontWeight.w500,
          ),
          errorStyle: const TextStyle(
            letterSpacing: 0.8,
            color: Colors.redAccent,
            fontWeight: FontWeight.w500,
          ),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: _getInitialScreen(),
    );
  }

  Widget _getInitialScreen() {
    if (_showOnboarding == null) {
      return const SplashScreen();
    }

    if (_showOnboarding!) {
      return const OnboardingScreen();
    }

    if (_loggedInEmployeeId != null) {
      return DashboardView(employeeId: _loggedInEmployeeId!);
    }

    // Default to app password entry for registered users
    return const AppPasswordEntryView();
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "PHOENICIAN",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 16),
              CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}