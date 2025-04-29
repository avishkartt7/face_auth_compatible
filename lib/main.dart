// lib/main.dart

import 'package:face_auth_compatible/onboarding/onboarding_screen.dart';
import 'package:face_auth_compatible/pin_entry/pin_entry_view.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/common/utils/extensions/size_extension.dart';
import 'package:face_auth_compatible/common/utils/screen_size_util.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool onboardingComplete = prefs.getBool('onboardingComplete') ?? false;

    setState(() {
      _showOnboarding = !onboardingComplete;
    });
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
      // Use a builder to initialize context
      home: Builder(
        builder: (context) {
          // Initialize the required contexts
          ScreenSizeUtil.context = context;
          CustomSnackBar.context = context;

          // Now return the appropriate start screen
          if (_showOnboarding == null) {
            return const SplashScreen();
          } else if (_showOnboarding!) {
            return const OnboardingScreen();
          } else {
            return const AppPasswordEntryView();
          }
        },
      ),
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