import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/common/utils/extensions/size_extension.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/pin_entry/user_profile_view.dart';
import 'package:face_auth_compatible/model/user_model.dart';
import 'package:flutter/material.dart';

class PinEntryView extends StatefulWidget {
  const PinEntryView({Key? key}) : super(key: key);

  @override
  State<PinEntryView> createState() => _PinEntryViewState();
}

class _PinEntryViewState extends State<PinEntryView> {
  final TextEditingController _pinController = TextEditingController();
  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    // Initialize context here as well for safety
    if (CustomSnackBar.context == null) {
      CustomSnackBar.context = context;
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: appBarColor,
        title: const Text("Employee PIN"),
        elevation: 0,
      ),
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
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "Enter your 4-digit employee PIN",
                  style: TextStyle(
                    color: primaryWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // Use fixed sizes instead of .sh for initial setup
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    obscureText: true,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: primaryWhite,
                      fontSize: 24,
                      letterSpacing: 15,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      counterText: "",
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                if (isLoading)
                  const CircularProgressIndicator(color: accentColor)
                else
                  _buildVerifyButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerifyButton() {
    return GestureDetector(
      onTap: _verifyPin,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 40,
          vertical: 16,
        ),
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(30),
        ),
        child: const Text(
          "Verify PIN",
          style: TextStyle(
            color: primaryWhite,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _verifyPin() async {
    if (_pinController.text.length != 4) {
      CustomSnackBar.errorSnackBar("Please enter a 4-digit PIN");
      return;
    }

    setState(() => isLoading = true);

    try {
      // Query Firestore for the employee with the given PIN
      final querySnapshot = await FirebaseFirestore.instance
          .collection("employees")
          .where("pin", isEqualTo: _pinController.text)
          .limit(1)
          .get();

      setState(() => isLoading = false);

      if (querySnapshot.docs.isEmpty) {
        CustomSnackBar.errorSnackBar("Invalid PIN. Please try again.");
        return;
      }

      // Employee found, create user profile from data
      final employeeData = querySnapshot.docs.first.data();
      final employee = UserModel(
        id: querySnapshot.docs.first.id,
        name: employeeData['name'] ?? 'Employee',
        // Add other fields as needed
      );

      // Navigate to profile page
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => UserProfileView(
              employeePin: _pinController.text,
              user: employee,
              isNewUser: employeeData['registrationCompleted'] != true,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      CustomSnackBar.errorSnackBar("Error: $e");
    }
  }
}