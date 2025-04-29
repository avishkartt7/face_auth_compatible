// lib/authenticate_face/user_password_setup_view.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/common/utils/extensions/size_extension.dart';
import 'package:face_auth_compatible/common/views/custom_button.dart';
import 'package:face_auth_compatible/constants/theme.dart';
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
    // Initialize context
    CustomSnackBar.context = context;

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
            padding: EdgeInsets.all(0.06.sw),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 0.1.sh,
                  color: Colors.white,
                ),
                SizedBox(height: 0.04.sh),
                const Text(
                  "Create a 4-digit password for quick app access",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 0.05.sh),
                _buildPasswordField(
                  controller: _passwordController,
                  label: "Enter Password",
                ),
                SizedBox(height: 0.03.sh),
                _buildPasswordField(
                  controller: _confirmPasswordController,
                  label: "Confirm Password",
                ),
                SizedBox(height: 0.05.sh),
                if (_isLoading)
                  const CircularProgressIndicator(color: accentColor)
                else
                  CustomButton(
                    text: "Create Password",
                    onTap: _createPassword,
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
        SizedBox(height: 0.01.sh),
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

  void _createPassword() async {
    // Validate inputs
    if (_passwordController.text.length != 4) {
      CustomSnackBar.errorSnackBar("Password must be exactly 4 digits");
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      CustomSnackBar.errorSnackBar("Passwords do not match");
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

      CustomSnackBar.successSnackBar("Password created successfully!");

      // Show completion dialog
      _showCompletionDialog();
    } catch (e) {
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar("Error creating password: $e");
    }
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Registration Complete"),
        content: const Text(
          "Your registration is now complete! You can use your app password to quickly log in next time.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Navigate to home screen (clear all routes)
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => const Scaffold(
                    body: Center(
                      child: Text("Registration Complete - Dashboard will be implemented next"),
                    ),
                  ),
                ),
                    (route) => false,
              );
            },
            child: const Text(
              "Get Started",
              style: TextStyle(color: accentColor),
            ),
          ),
        ],
      ),
    );
  }
}
