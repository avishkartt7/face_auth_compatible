// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/onboarding/onboarding_screen.dart';
import 'package:face_auth_compatible/pin_entry/pin_entry_view.dart';
import 'package:face_auth_compatible/pin_entry/app_password_entry_view.dart';
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

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool onboardingComplete = prefs.getBool('onboardingComplete') ?? false;

    setState(() {
      // If onboarding not completed, show onboarding screens
      if (!onboardingComplete) {
        _showOnboarding = true;
        return;
      }

      // Check if user is registered
      _checkRegistrationStatus();
    });
  }

  Future<void> _checkRegistrationStatus() async {
    try {
      QuerySnapshot userQuery = await FirebaseFirestore.instance
          .collection('employees')
          .where('registrationCompleted', isEqualTo: true)
          .limit(1)
          .get();

      setState(() {
        // If no registered user found, show PIN entry
        // Otherwise show app password entry
        _showOnboarding = userQuery.docs.isEmpty;
      });
    } catch (e) {
      print("Error checking registration status: $e");
      setState(() {
        _showOnboarding = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Face Authentication App',
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
      home: _showOnboarding == null
          ? const SplashScreen()
          : _showOnboarding!
          ? const OnboardingScreen()  // Show onboarding for first time
          : const AppPasswordEntryView(),  // Show app password for registered users
    );
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
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }
}