// lib/authenticate_face/user_password_setup_view.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/common/utils/extensions/size_extension.dart';
import 'package:face_auth_compatible/common/views/custom_button.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/register_face/registration_complete_view.dart';
import 'package:flutter/material.dart';

class UserPasswordSetupView extends StatefulWidget {
  final String employeeId;
  final String employeePin;

  const UserPasswordSetupView({
    Key? key,
    required this.employeeId,
    required this.employeePin,
  }) : super(key: key);

  @override
  State<UserPasswordSetupView> createState() => _UserPasswordSetupViewState();
}

class _UserPasswordSetupViewState extends State<UserPasswordSetupView> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use context directly instead of setting it in a global variable
    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: appBarColor,
        title: const Text("Create App Password"),
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
            padding: EdgeInsets.all(screenWidth * 0.06),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: screenHeight * 0.1,
                  color: Colors.white,
                ),
                SizedBox(height: screenHeight * 0.04),
                const Text(
                  "Create a 4-digit password for quick app access",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: screenHeight * 0.05),
                _buildPasswordField(
                  controller: _passwordController,
                  label: "Enter Password",
                ),
                SizedBox(height: screenHeight * 0.03),
                _buildPasswordField(
                  controller: _confirmPasswordController,
                  label: "Confirm Password",
                ),
                SizedBox(height: screenHeight * 0.05),
                if (_isLoading)
                  const CircularProgressIndicator(color: accentColor)
                else
                  CustomButton(
                    text: "Create Password",
                    onTap: () => _createPassword(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
  }) {
    final double screenHeight = MediaQuery.of(context).size.height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
        SizedBox(height: screenHeight * 0.01),
        TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
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
      ],
    );
  }

  void _createPassword(BuildContext context) async {
    // Validate inputs
    if (_passwordController.text.length != 4) {
      CustomSnackBar.errorSnackBar(context, "Password must be exactly 4 digits");
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      CustomSnackBar.errorSnackBar(context, "Passwords do not match");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Update the employee document with the app password
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .update({
        'appPassword': _passwordController.text,
        'registrationCompleted': true,
      });

      setState(() => _isLoading = false);

      CustomSnackBar.successSnackBar(context, "Password created successfully!");

      // Navigate to the completion screen
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const RegistrationCompleteView(),
          ),
              (route) => false, // This removes all previous routes
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar(context, "Error creating password: $e");
    }
  }
}