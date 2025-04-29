// lib/authenticate_face/authenticate_face_view.dart

import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/authenticate_face/scanning_animation/animated_view.dart';
import 'package:face_auth_compatible/authenticate_face/user_password_setup_view.dart'; // New import
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/common/utils/extensions/size_extension.dart';
import 'package:face_auth_compatible/common/utils/extract_face_feature.dart';
import 'package:face_auth_compatible/common/views/camera_view.dart';
import 'package:face_auth_compatible/common/views/custom_button.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/model/user_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_face_api/face_api.dart' as regula;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class AuthenticateFaceView extends StatefulWidget {
  final String? employeeId; // Made optional for backward compatibility
  final String? employeePin; // Made optional for backward compatibility
  final bool isRegistrationValidation;

  const AuthenticateFaceView({
    Key? key,
    this.employeeId,
    this.employeePin,
    this.isRegistrationValidation = false,
  }) : super(key: key);

  @override
  State<AuthenticateFaceView> createState() => _AuthenticateFaceViewState();
}

class _AuthenticateFaceViewState extends State<AuthenticateFaceView> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  FaceFeatures? _faceFeatures;
  var image1 = regula.MatchFacesImage();
  var image2 = regula.MatchFacesImage();

  final TextEditingController _pinController = TextEditingController();
  String _similarity = "";
  bool _canAuthenticate = false;
  Map<String, dynamic>? employeeData;
  bool isMatching = false;
  int trialNumber = 1;

  @override
  void initState() {
    super.initState();
    // If employeeId is provided, fetch that specific employee data
    if (widget.employeeId != null) {
      _fetchEmployeeData(widget.employeeId!);
    }
  }

  Future<void> _fetchEmployeeData(String employeeId) async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(employeeId)
          .get();

      if (doc.exists) {
        setState(() {
          employeeData = doc.data() as Map<String, dynamic>;
        });
      } else {
        CustomSnackBar.errorSnackBar("Employee data not found");
      }
    } catch (e) {
      CustomSnackBar.errorSnackBar("Error: $e");
    }
  }

  @override
  void dispose() {
    _faceDetector.close();
    _audioPlayer.dispose();
    _pinController.dispose();
    super.dispose();
  }

  get _playScanningAudio => _audioPlayer
    ..setReleaseMode(ReleaseMode.loop)
    ..play(AssetSource("scan_beep.wav"));

  get _playFailedAudio => _audioPlayer
    ..stop()
    ..setReleaseMode(ReleaseMode.release)
    ..play(AssetSource("failed.mp3"));

  @override
  Widget build(BuildContext context) {
    // Make sure the context is set for screen size utilities
    CustomSnackBar.context = context;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: appBarColor,
        title: Text(widget.isRegistrationValidation
            ? "Verify Your Face"
            : "Authenticate Face"),
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constrains) => Stack(
          children: [
            Container(
              width: constrains.maxWidth,
              height: constrains.maxHeight,
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
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (widget.isRegistrationValidation)
                      Padding(
                        padding: EdgeInsets.only(bottom: 0.02.sh),
                        child: Text(
                          "Let's verify your face was registered correctly",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    Container(
                      height: widget.isRegistrationValidation ? 0.75.sh : 0.82.sh,
                      width: double.infinity,
                      padding: EdgeInsets.fromLTRB(0.05.sw, 0.025.sh, 0.05.sw, 0),
                      decoration: BoxDecoration(
                        color: overlayContainerClr,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(0.03.sh),
                          topRight: Radius.circular(0.03.sh),
                        ),
                      ),
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              CameraView(
                                onImage: (image) {
                                  _setImage(image);
                                },
                                onInputImage: (inputImage) async {
                                  setState(() => isMatching = true);
                                  _faceFeatures = await extractFaceFeatures(
                                      inputImage, _faceDetector);
                                  setState(() => isMatching = false);
                                },
                              ),
                              if (isMatching)
                                Align(
                                  alignment: Alignment.center,
                                  child: Padding(
                                    padding: EdgeInsets.only(top: 0.064.sh),
                                    child: const AnimatedView(),
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          if (_canAuthenticate)
                            CustomButton(
                              text: widget.isRegistrationValidation
                                  ? "Verify Face"
                                  : "Authenticate",
                              onTap: () {
                                setState(() => isMatching = true);
                                _playScanningAudio;
                                if (widget.employeeId != null) {
                                  _matchFaceWithStored();
                                } else {
                                  _promptForPin();
                                }
                              },
                            ),
                          SizedBox(height: 0.038.sh),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Future _setImage(Uint8List imageToAuthenticate) async {
    image2.bitmap = base64Encode(imageToAuthenticate);
    image2.imageType = regula.ImageType.PRINTED;

    setState(() {
      _canAuthenticate = true;
    });
  }

  void _promptForPin() {
    _audioPlayer.stop();
    setState(() => isMatching = false);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Enter Your PIN"),
          content: TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 4,
            obscureText: true,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: "4-digit PIN",
              counterText: "",
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() => isMatching = false);
              },
              child: const Text(
                "Cancel",
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () {
                if (_pinController.text.length != 4) {
                  CustomSnackBar.errorSnackBar("Please enter a 4-digit PIN");
                  return;
                }
                Navigator.of(context).pop();
                setState(() => isMatching = true);
                _fetchEmployeeByPin(_pinController.text);
              },
              child: const Text(
                "Verify",
                style: TextStyle(color: accentColor),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchEmployeeByPin(String pin) async {
    try {
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('employees')
          .where('pin', isEqualTo: pin)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        setState(() => isMatching = false);
        _playFailedAudio;
        CustomSnackBar.errorSnackBar("Invalid PIN. Please try again.");
        return;
      }

      // Get the employee document
      final employeeDoc = snapshot.docs.first;
      final String employeeId = employeeDoc.id;

      // Set the employee data
      setState(() {
        employeeData = employeeDoc.data() as Map<String, dynamic>;
      });

      // Proceed with face matching
      _matchFaceWithStored();
    } catch (e) {
      setState(() => isMatching = false);
      _playFailedAudio;
      CustomSnackBar.errorSnackBar("Error: $e");
    }
  }

  Future<void> _matchFaceWithStored() async {
    if (employeeData == null || !employeeData!.containsKey('image')) {
      _showFailureDialog(
        title: "Registration Error",
        description: "No registered face found for this employee.",
      );
      return;
    }

    // Get the stored face image
    image1.bitmap = employeeData!['image'];
    image1.imageType = regula.ImageType.PRINTED;

    // Face comparing logic
    var request = regula.MatchFacesRequest();
    request.images = [image1, image2];

    try {
      dynamic value = await regula.FaceSDK.matchFaces(jsonEncode(request));
      var response = regula.MatchFacesResponse.fromJson(json.decode(value));

      dynamic str = await regula.FaceSDK.matchFacesSimilarityThresholdSplit(
          jsonEncode(response!.results), 0.75);

      var split = regula.MatchFacesSimilarityThresholdSplit.fromJson(json.decode(str));

      setState(() {
        _similarity = split!.matchedFaces.isNotEmpty
            ? (split.matchedFaces[0]!.similarity! * 100).toStringAsFixed(2)
            : "error";
        log("similarity: $_similarity");
      });

      // Check if faces match
      if (_similarity != "error" && double.parse(_similarity) > 90.00) {
        _audioPlayer
          ..stop()
          ..setReleaseMode(ReleaseMode.release)
          ..play(AssetSource("success.mp3"));

        setState(() {
          trialNumber = 1;
          isMatching = false;
        });

        // Face authentication successful
        if (widget.isRegistrationValidation) {
          // If this is part of the registration flow, move to password setup
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => UserPasswordSetupView(
                  employeeId: widget.employeeId!,
                  employeePin: widget.employeePin!,
                ),
              ),
            );
          }
        } else {
          // If this is a regular authentication, show success
          _showSuccessDialog();
        }
      } else {
        // Face doesn't match
        _showFailureDialog(
          title: "Authentication Failed",
          description: "Face doesn't match. Please try again.",
        );
      }
    } catch (e) {
      setState(() => isMatching = false);
      _playFailedAudio;
      CustomSnackBar.errorSnackBar("Error during face matching: $e");
    }
  }

  _showSuccessDialog() {
    _audioPlayer.stop();
    setState(() => isMatching = false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Authentication Successful"),
        content: Text("Welcome, ${employeeData?['name'] ?? 'User'}!"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // Navigate to the main dashboard (to be implemented)
            },
            child: const Text(
              "Continue",
              style: TextStyle(color: accentColor),
            ),
          )
        ],
      ),
    );
  }

  _showFailureDialog({
    required String title,
    required String description,
  }) {
    _playFailedAudio;
    setState(() => isMatching = false);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                "Ok",
                style: TextStyle(color: accentColor),
              ),
            )
          ],
        );
      },
    );
  }
}
