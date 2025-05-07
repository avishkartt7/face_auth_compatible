// lib/register_face/register_face_view.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:face_auth_compatible/common/utils/extract_face_feature.dart';
import 'package:face_auth_compatible/common/views/camera_view.dart';
import 'package:face_auth_compatible/common/views/custom_button.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/model/user_model.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/authenticate_face/authenticate_face_view.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class RegisterFaceView extends StatefulWidget {
  final String employeeId;
  final String employeePin;

  const RegisterFaceView({
    Key? key,
    required this.employeeId,
    required this.employeePin,
  }) : super(key: key);

  @override
  State<RegisterFaceView> createState() => _RegisterFaceViewState();
}

class _RegisterFaceViewState extends State<RegisterFaceView> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  String? _image;
  FaceFeatures? _faceFeatures;
  bool isRegistering = false;

  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Get screen dimensions directly from MediaQuery
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    // Set context for global utilities
    CustomSnackBar.context = context;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: appBarColor,
        title: const Text("Register Your Face"),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              height: screenHeight * 0.82,
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                  screenWidth * 0.05,
                  screenHeight * 0.025,
                  screenWidth * 0.05,
                  screenHeight * 0.04
              ),
              decoration: BoxDecoration(
                color: overlayContainerClr,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(screenHeight * 0.03),
                  topRight: Radius.circular(screenHeight * 0.03),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Text(
                    "Let's register your face for authentication",
                    style: TextStyle(
                      color: primaryWhite,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  const Text(
                    "Please look directly at the camera in good lighting",
                    style: TextStyle(
                      color: primaryWhite,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: screenHeight * 0.02),
                  CameraView(
                    onImage: (image) {
                      setState(() {
                        _image = base64Encode(image);
                      });
                    },
                    onInputImage: (inputImage) async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(
                            color: accentColor,
                          ),
                        ),
                      );
                      _faceFeatures =
                      await extractFaceFeatures(inputImage, _faceDetector);
                      setState(() {});
                      if (mounted) Navigator.of(context).pop();
                    },
                  ),
                  const Spacer(),
                  if (isRegistering)
                    const CircularProgressIndicator(color: accentColor)
                  else if (_image != null)
                    CustomButton(
                      text: "Register Face",
                      onTap: () => _registerFace(context),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _registerFace(BuildContext context) async {
    if (_image == null || _faceFeatures == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please capture your face first"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => isRegistering = true);

    try {
      // Make sure we have clean base64 data without data URL prefix
      String cleanedImage = _image!;
      if (cleanedImage.contains('data:image') && cleanedImage.contains(',')) {
        cleanedImage = cleanedImage.split(',')[1];
        debugPrint("Cleaned data URL format to pure base64");
      }

      // Save to Firestore
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .update({
        'image': cleanedImage,
        'faceFeatures': _faceFeatures!.toJson(),
        'faceRegistered': true,
      });

      // Save locally for offline use
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('employee_image_${widget.employeeId}', cleanedImage);
      debugPrint("Saved face image to SharedPreferences, length: ${cleanedImage.length}");

      setState(() => isRegistering = false);



      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Face registered successfully!"),
          backgroundColor: accentColor,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Navigate to face authentication for verification
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AuthenticateFaceView(
              employeeId: widget.employeeId,
              employeePin: widget.employeePin,
              isRegistrationValidation: true,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => isRegistering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error registering face: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}