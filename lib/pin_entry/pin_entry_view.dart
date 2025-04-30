// lib/pin_entry/pin_entry_view.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/pin_entry/user_profile_view.dart';
import 'package:face_auth_compatible/model/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';


class PinEntryView extends StatefulWidget {
  const PinEntryView({Key? key}) : super(key: key);

  @override
  State<PinEntryView> createState() => _PinEntryViewState();
}

class _PinEntryViewState extends State<PinEntryView> with SingleTickerProviderStateMixin {
  final List<TextEditingController> _controllers = List.generate(
    4,
        (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    4,
        (index) => FocusNode(),
  );

  bool _isLoading = false;
  bool _isPinEntered = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animation for the verification button
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );

    // Set up listeners for the PIN fields
    for (int i = 0; i < 4; i++) {
      _focusNodes[i].addListener(() {
        setState(() {});
      });

      _controllers[i].addListener(() {
        // Check if all PIN fields are filled
        _checkPinCompletion();

        // Auto advance to next field
        if (_controllers[i].text.length == 1 && i < 3) {
          FocusScope.of(context).requestFocus(_focusNodes[i + 1]);
        }
      });
    }
  }

  void _checkPinCompletion() {
    bool allFilled = true;
    for (var controller in _controllers) {
      if (controller.text.isEmpty) {
        allFilled = false;
        break;
      }
    }

    if (allFilled != _isPinEntered) {
      setState(() {
        _isPinEntered = allFilled;
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    _animationController.dispose();
    super.dispose();
  }

  String get _pin => _controllers.map((e) => e.text).join();

  void _clearPin() {
    for (var controller in _controllers) {
      controller.clear();
    }
    setState(() {
      _isPinEntered = false;
    });
    FocusScope.of(context).requestFocus(_focusNodes[0]);
  }

  void _verifyPin() async {
    if (_pin.length != 4) {
      _showError("Please enter a 4-digit PIN");
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.mediumImpact();

    try {
      // Query Firestore for the employee with the given PIN
      final querySnapshot = await FirebaseFirestore.instance
          .collection("employees")
          .where("pin", isEqualTo: _pin)
          .limit(1)
          .get();

      setState(() => _isLoading = false);

      if (querySnapshot.docs.isEmpty) {
        _showError("Invalid PIN. Please try again.");
        _animateErrorShake();
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
              employeePin: _pin,
              user: employee,
              isNewUser: employeeData['registrationCompleted'] != true,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("Error: $e");
    }
  }

  void _showError(String message) {
    CustomSnackBar.errorSnackBar(message);
  }

  void _animateErrorShake() {
    // Simple shake animation for incorrect PIN
    final shakeCount = 3;
    final shakeDuration = 50;
    for (var i = 0; i < shakeCount * 2; i++) {
      Future.delayed(Duration(milliseconds: i * shakeDuration), () {
        if (mounted) {
          // Animate container left/right slightly
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialize context here as well for safety
    if (CustomSnackBar.context == null) {
      CustomSnackBar.context = context;
    }

    return Scaffold(
      // Ensure we have a clean layout without any debug banners
      resizeToAvoidBottomInset: false,
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
          // Make sure content stays within safe area bounds
          maintainBottomViewPadding: true,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),

              // App logo or icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Colors.white,
                  size: 40,
                ),
              ),

              const SizedBox(height: 30),

              // Title and instruction
              const Text(
                "Employee Authentication",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  "Enter your 4-digit PIN to continue",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 40),

              // PIN input fields
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    4,
                        (index) => _buildPinField(index),
                  ),
                ),
              ),

              // Conditional verification UI
              if (_isPinEntered) ...[
                const SizedBox(height: 40),
                SvgPicture.asset(
                  'assets/images/pin_success.svg', // Your confirmation SVG
                  height: 120,
                  width: 120,
                ),
                const SizedBox(height: 20),
                const Text(
                  "PIN entered successfully",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 40),
                SvgPicture.asset(
                  'assets/images/pin_entry_image.svg', // Your PIN entry SVG
                  height: 140,
                  width: 140,
                ),
              ],

              const Spacer(),

              // Action buttons
              if (_isLoading)
                const CircularProgressIndicator(color: Colors.white)
              else if (_isPinEntered)
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Clear button
                      GestureDetector(
                        onTap: _clearPin,
                        child: Container(
                          width: 140,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: const Center(
                            child: Text(
                              "Clear",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 20),

                      // Next button
                      GestureDetector(
                        onTapDown: (_) => _animationController.forward(),
                        onTapUp: (_) {
                          _animationController.reverse();
                          _verifyPin();
                        },
                        onTapCancel: () => _animationController.reverse(),
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            width: 140,
                            height: 50,
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor.withOpacity(0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                "Next",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Text(
                    "If you've forgotten your PIN, please contact your administrator",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinField(int index) {
    return Container(
      width: 50,
      height: 50,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _controllers[index].text.isNotEmpty
            ? Colors.white
            : Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        obscureText: true,
        style: TextStyle(
          color: _controllers[index].text.isNotEmpty
              ? accentColor
              : Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        decoration: const InputDecoration(
          counterText: "",
          border: InputBorder.none,
        ),
        onChanged: (value) {
          if (value.isEmpty && index > 0) {
            FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
          }
        },
      ),
    );
  }
}