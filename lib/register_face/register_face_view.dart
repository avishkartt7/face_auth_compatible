import 'dart:convert';

import 'package:face_auth_compatible/common/utils/extract_face_feature.dart';
import 'package:face_auth_compatible/common/views/camera_view.dart';
import 'package:face_auth_compatible/common/views/custom_button.dart';
import 'package:face_auth_compatible/common/utils/extensions/size_extension.dart';
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
              height: 0.82.sh,
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(0.05.sw, 0.025.sh, 0.05.sw, 0.04.sh),
              decoration: BoxDecoration(
                color: overlayContainerClr,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(0.03.sh),
                  topRight: Radius.circular(0.03.sh),
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
                  SizedBox(height: 0.02.sh),
                  const Text(
                    "Please look directly at the camera in good lighting",
                    style: TextStyle(
                      color: primaryWhite,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 0.02.sh),
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
                      onTap: _registerFace,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _registerFace() async {
    if (_image == null || _faceFeatures == null) {
      CustomSnackBar.errorSnackBar("Please capture your face first");
      return;
    }

    setState(() => isRegistering = true);

    try {
      // Save face data to Firestore
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .update({
        'image': _image,
        'faceFeatures': _faceFeatures!.toJson(),
        'faceRegistered': true,
      });

      setState(() => isRegistering = false);

      // Show success message
      CustomSnackBar.successSnackBar("Face registered successfully!");

      // Navigate to face authentication for verification - keep the old API for now
      if (mounted) {
        // Update in RegisterFaceView._registerFace method (inside the if (mounted) block)

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
      CustomSnackBar.errorSnackBar("Error registering face: $e");
    }
  }
}