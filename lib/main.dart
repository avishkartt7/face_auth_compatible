// lib/main.dart

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
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
      // Verify user exists in Firestore
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(authenticatedUserId)
            .get();

        if (doc.exists) {
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

    // Check if any user is registered
    try {
      QuerySnapshot userQuery = await FirebaseFirestore.instance
          .collection('employees')
          .where('registrationCompleted', isEqualTo: true)
          .limit(1)
          .get();

      setState(() {
        // If users exist, show app password entry, otherwise show PIN entry
        _showOnboarding = false;
      });
    } catch (e) {
      print("Error checking registration status: $e");
      setState(() {
        _showOnboarding = true;
      });
    }
  }

  Future<void> _initializeLocationData() async {
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