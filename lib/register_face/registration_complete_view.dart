// lib/register_face/registration_complete_view.dart

import 'package:flutter/material.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:face_auth_compatible/pin_entry/pin_entry_view.dart';

class RegistrationCompleteView extends StatelessWidget {
  const RegistrationCompleteView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: scaffoldBottomGradientClr,
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
        width: double.infinity,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Using a placeholder for now - replace with your actual SVG
                // If you don't have the SVG file yet, use an Icon instead

                // Uncomment this when you have the SVG file
                // SvgPicture.asset(
                //   'assets/images/registration_complete.svg',
                //   height: 250,
                // ),

                // Use this Icon as a placeholder until you have the SVG
                Icon(
                  Icons.check_circle_outline,
                  size: 150,
                  color: Colors.white,
                ),

                const SizedBox(height: 40),

                const Text(
                  "Registration Complete!",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 16),

                const Text(
                  "Your account has been successfully registered. You can now use the app with facial authentication.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 60),

                // Using a direct ElevatedButton to avoid potential issues with CustomButton
                ElevatedButton(
                  onPressed: () {
                    // Navigate to the login screen (PIN entry view)
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (context) => const PinEntryView(),
                      ),
                          (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    "Get Started",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}