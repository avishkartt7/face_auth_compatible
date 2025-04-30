// lib/pin_entry/app_password_entry_view.dart

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/dashboard/dashboard_view.dart';

class AppPasswordEntryView extends StatefulWidget {
  const AppPasswordEntryView({Key? key}) : super(key: key);

  @override
  State<AppPasswordEntryView> createState() => _AppPasswordEntryViewState();
}

class _AppPasswordEntryViewState extends State<AppPasswordEntryView> {
  final List<TextEditingController> _controllers = List.generate(
    4,
        (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    4,
        (index) => FocusNode(),
  );

  bool _isLoading = false;
  bool _isPasswordComplete = false;

  @override
  void initState() {
    super.initState();

    for (int i = 0; i < 4; i++) {
      _controllers[i].addListener(() {
        _checkPasswordCompletion();

        if (_controllers[i].text.length == 1 && i < 3) {
          FocusScope.of(context).requestFocus(_focusNodes[i + 1]);
        }
      });
    }
  }

  void _checkPasswordCompletion() {
    bool isComplete = _controllers.every((controller) => controller.text.isNotEmpty);
    if (isComplete != _isPasswordComplete) {
      setState(() {
        _isPasswordComplete = isComplete;
      });
    }
  }

  Future<void> _verifyPassword() async {
    String enteredPassword = _controllers.map((e) => e.text).join();

    setState(() => _isLoading = true);

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('employees')
          .where('appPassword', isEqualTo: enteredPassword)
          .limit(1)
          .get();

      setState(() => _isLoading = false);

      if (querySnapshot.docs.isEmpty) {
        CustomSnackBar.errorSnackBar('Invalid app password. Please try again.');
        _clearPassword();
        return;
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const DashboardView(),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar('Error verifying password: $e');
    }
  }

  void _clearPassword() {
    for (var controller in _controllers) {
      controller.clear();
    }
    setState(() {
      _isPasswordComplete = false;
    });
    FocusScope.of(context).requestFocus(_focusNodes[0]);
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
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
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),

                  // Authentication SVG Image
                  SvgPicture.asset(
                    'assets/images/authentication.svg',
                    height: 200,
                  ),

                  const SizedBox(height: 40),

                  // Title with glowing effect
                  Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withOpacity(0.1),
                          blurRadius: 20,
                          spreadRadius: -5,
                        ),
                      ],
                    ),
                    child: const Text(
                      "Enter App Password",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Subtitle
                  Text(
                    "Please enter your 4-digit app password to continue",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Password Fields
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(
                      4,
                          (index) => _buildPasswordField(index),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Verify Button or Loading Indicator
                  if (_isLoading)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    )
                  else if (_isPasswordComplete)
                    _buildVerifyButton(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordField(int index) {
    return Container(
      width: 60,
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        obscureText: true,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          counterText: "",
          border: InputBorder.none,
          fillColor: Colors.white.withOpacity(0.05),
          filled: true,
        ),
        onChanged: (value) {
          if (value.isNotEmpty && index < 3) {
            FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
          } else if (value.isEmpty && index > 0) {
            FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
          }
          _checkPasswordCompletion();
        },
      ),
    );
  }

  Widget _buildVerifyButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.3),
            blurRadius: 15,
            spreadRadius: -5,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _verifyPassword,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          padding: const EdgeInsets.symmetric(
            horizontal: 50,
            vertical: 16,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: const Text(
          "Verify",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}