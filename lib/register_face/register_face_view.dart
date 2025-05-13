// lib/register_face/register_face_view.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
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
import 'package:path_provider/path_provider.dart';
import 'package:flutter_face_api/face_api.dart' as regula;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';
import 'package:face_auth_compatible/services/service_locator.dart';

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
  bool _isRegistering = false;
  bool _isOfflineMode = false;
  late ConnectivityService _connectivityService;

  // Add debug info variables
  String _debugStatus = "Waiting for face capture";
  String _imageQuality = "Not captured";

  @override
  void initState() {
    super.initState();
    _connectivityService = getIt<ConnectivityService>();
    _checkConnectivity();

    // Listen to connectivity changes
    _connectivityService.connectionStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _isOfflineMode = status == ConnectionStatus.offline;
          _debugStatus = "Connectivity changed: ${status.toString()}";
        });
      }
    });

    debugPrint("FACE REG: Initialized RegisterFaceView for employeeId: ${widget.employeeId}");
  }

  Future<void> _checkConnectivity() async {
    try {
      // Use the service locator's connectivity service
      bool isOnline = await _connectivityService.checkConnectivity();

      setState(() {
        _isOfflineMode = !isOnline;
      });

      debugPrint("FACE REG: ${_isOfflineMode ? 'Offline' : 'Online'} mode detected");
    } catch (e) {
      setState(() {
        _isOfflineMode = false; // Default to online mode if check fails
      });
      debugPrint("FACE REG: Error checking connectivity: $e");
    }
  }

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
        actions: [
          // Add debug button
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: _showDebugInfo,
          ),
          // Add connectivity refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkConnectivity,
          ),
        ],
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
            // Status indicator showing online/offline mode
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _isOfflineMode
                    ? Colors.orange.withOpacity(0.2)
                    : Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isOfflineMode ? Icons.offline_bolt : Icons.cloud_done,
                    color: _isOfflineMode ? Colors.orange : Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isOfflineMode
                        ? "Offline Mode - Registration will be saved locally"
                        : "Online Mode - Registration will sync to cloud",
                    style: TextStyle(
                      color: _isOfflineMode ? Colors.orange : Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
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
                        _debugStatus = "Face image captured";
                        _imageQuality = "Image size: ${image.length} bytes";
                      });

                      // Test image quality and format
                      _testImageQuality(_image!);
                    },
                    onInputImage: (inputImage) async {
                      setState(() {
                        _debugStatus = "Processing face features...";
                      });

                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(
                            color: accentColor,
                          ),
                        ),
                      );

                      try {
                        _faceFeatures = await extractFaceFeatures(inputImage, _faceDetector);

                        // Validate face features
                        if (_faceFeatures == null) {
                          throw Exception("Failed to extract face features");
                        }

                        // Verify face is properly detected
                        bool hasValidFace = _validateFaceFeatures(_faceFeatures!);
                        if (!hasValidFace) {
                          throw Exception("Face features are incomplete - please try again with better lighting");
                        }

                        setState(() {
                          _debugStatus = "Face features extracted successfully";
                        });
                      } catch (e) {
                        setState(() {
                          _debugStatus = "Error extracting face features: $e";
                        });
                        debugPrint("FACE REG: Error extracting face features: $e");
                      }

                      if (mounted) Navigator.of(context).pop();
                    },
                  ),
                  const Spacer(),
                  _isRegistering
                      ? const CircularProgressIndicator(color: accentColor)
                      : (_image != null && _faceFeatures != null)
                      ? CustomButton(
                    text: "Register Face",
                    onTap: () => _registerFace(context),
                  )
                      : Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      "Capture your face to continue",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to validate face features have all required landmarks
  bool _validateFaceFeatures(FaceFeatures features) {
    // Check that at least essential features are present
    bool hasEyes = features.leftEye?.x != null && features.rightEye?.x != null;
    bool hasNose = features.noseBase?.x != null;
    bool hasMouth = features.leftMouth?.x != null && features.rightMouth?.x != null;

    return hasEyes && hasNose && hasMouth;
  }

  void _testImageQuality(String base64Image) {
    try {
      debugPrint("FACE REG: Testing image quality");

      // Check if it's in data URL format
      if (base64Image.contains('data:image') && base64Image.contains(',')) {
        debugPrint("FACE REG: WARNING - Image is in data URL format, should be cleaned");
        setState(() {
          _imageQuality += " (data URL format)";
        });
      }

      // Try to decode base64
      try {
        final imageBytes = base64Decode(
            base64Image.contains('data:image') && base64Image.contains(',')
                ? base64Image.split(',')[1]
                : base64Image
        );

        debugPrint("FACE REG: Successfully decoded image: ${imageBytes.length} bytes");

        // Evaluate image size
        if (imageBytes.length < 20000) {
          setState(() {
            _imageQuality += " - Low quality, may cause authentication issues";
          });
          debugPrint("FACE REG: Image quality may be too low for reliable authentication");
        } else if (imageBytes.length > 200000) {
          setState(() {
            _imageQuality += " - High quality";
          });
          debugPrint("FACE REG: High quality image captured");
        } else {
          setState(() {
            _imageQuality += " - Good quality";
          });
          debugPrint("FACE REG: Good quality image captured");
        }

      } catch (e) {
        debugPrint("FACE REG: Failed to decode base64 image: $e");
        setState(() {
          _imageQuality += " - ERROR: Invalid base64 format";
        });
      }

    } catch (e) {
      debugPrint("FACE REG: Error testing image quality: $e");
    }
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

    setState(() {
      _isRegistering = true;
      _debugStatus = "Registering face...";
    });

    try {
      // Make sure we have clean base64 data without data URL prefix
      String cleanedImage = _image!;

      debugPrint("FACE REG: Processing image for registration, original length: ${cleanedImage.length}");

      if (cleanedImage.contains('data:image') && cleanedImage.contains(',')) {
        cleanedImage = cleanedImage.split(',')[1];
        debugPrint("FACE REG: Cleaned data URL format to pure base64");
      }

      // Validate it's proper base64 before saving
      try {
        Uint8List decodedImage = base64Decode(cleanedImage);
        debugPrint("FACE REG: Validated as proper base64 before saving, decoded length: ${decodedImage.length} bytes");
      } catch (e) {
        debugPrint("FACE REG: Error: Invalid base64 format: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error processing image format: $e"),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isRegistering = false;
          _debugStatus = "Error: Invalid image format";
        });
        return;
      }

      // Always save locally for offline use
      final prefs = await SharedPreferences.getInstance();

      // 1. Save the base64 image for Regula SDK (online mode)
      await prefs.setString('employee_image_${widget.employeeId}', cleanedImage);
      debugPrint("FACE REG: Saved face image locally (length: ${cleanedImage.length})");

      // 2. Save the ML Kit face features for offline authentication
      await prefs.setString('employee_face_features_${widget.employeeId}',
          jsonEncode(_faceFeatures!.toJson()));
      debugPrint("FACE REG: Saved ML Kit face features for offline authentication");

      // 3. Save a face token to indicate registration is complete
      await prefs.setBool('face_registered_${widget.employeeId}', true);

      // Check connectivity again before Firebase update
      await _checkConnectivity();

      // Save to Firebase if online
      if (!_isOfflineMode) {
        debugPrint("FACE REG: Attempting to save to Firebase (online mode)");

        try {
          await FirebaseFirestore.instance
              .collection('employees')
              .doc(widget.employeeId)
              .update({
            'image': cleanedImage, // Store clean base64
            'faceFeatures': _faceFeatures!.toJson(),
            'faceRegistered': true, // This is the key field that was missing
          });

          debugPrint("FACE REG: Successfully saved to Firebase with faceRegistered = true");
        } catch (e) {
          debugPrint("FACE REG: Error saving to Firestore: $e");

          // Show warning but don't fail the registration
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Warning: Could not sync to cloud. Data saved locally: $e"),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      } else {
        debugPrint("FACE REG: Offline mode - skipping Firebase update");

        // Create a local flag for syncing later
        await prefs.setBool('pending_face_registration_${widget.employeeId}', true);
      }

      setState(() {
        _isRegistering = false;
        _debugStatus = "Face registered successfully";
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isOfflineMode
                ? "Face registered successfully (offline mode)"
                : "Face registered successfully"),
            backgroundColor: accentColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

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
      setState(() {
        _isRegistering = false;
        _debugStatus = "Error registering face: $e";
      });

      debugPrint("FACE REG: Error registering face: $e");

      if (mounted) {
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

  // Prepare image for Regula SDK (used in online authentication)
  Future<void> _prepareRegulaSdkImage(String base64Image) async {
    try {
      debugPrint("FACE REG: Preparing image for Regula SDK compatibility");

      // We're not initializing or testing with Regula SDK during registration
      // Just log that we're storing the image for online authentication later
      debugPrint("FACE REG: Image prepared for future online authentication with Regula SDK");
    } catch (e) {
      debugPrint("FACE REG: Error preparing for Regula SDK: $e");
      // Continue anyway as we'll rely on ML Kit for offline auth
    }
  }

  void _showDebugInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Face Registration Debug Info"),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDebugInfoRow("Employee ID", widget.employeeId),
              _buildDebugInfoRow("Offline Mode", _isOfflineMode.toString()),
              _buildDebugInfoRow("Status", _debugStatus),
              _buildDebugInfoRow("Image Captured", (_image != null).toString()),
              _buildDebugInfoRow("Image Quality", _imageQuality),
              _buildDebugInfoRow("Face Features Extracted", (_faceFeatures != null).toString()),
              if (_faceFeatures != null) ...[
                _buildDebugInfoRow("  - Eyes Detected",
                    "${_faceFeatures!.leftEye?.x != null && _faceFeatures!.rightEye?.x != null}"),
                _buildDebugInfoRow("  - Nose Detected",
                    "${_faceFeatures!.noseBase?.x != null}"),
                _buildDebugInfoRow("  - Mouth Detected",
                    "${_faceFeatures!.leftMouth?.x != null && _faceFeatures!.rightMouth?.x != null}"),
              ],
              if (_image != null) ...[
                const Divider(),
                const Text("Image Details:", style: TextStyle(fontWeight: FontWeight.bold)),
                _buildDebugInfoRow("Length", "${_image!.length} chars"),
                _buildDebugInfoRow("Is Data URL Format",
                    (_image!.contains('data:image') && _image!.contains(',')).toString()),
                FutureBuilder<bool>(
                  future: _testBase64Validity(_image!),
                  builder: (context, snapshot) {
                    return _buildDebugInfoRow("Valid Base64",
                        snapshot.data?.toString() ?? "Checking...");
                  },
                ),
              ],
              const Divider(),
              const Text("Local Storage Test:", style: TextStyle(fontWeight: FontWeight.bold)),
              FutureBuilder<String?>(
                future: SharedPreferences.getInstance().then(
                        (prefs) => prefs.getString('employee_image_${widget.employeeId}')
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDebugInfoRow("Stored Image Found",
                          (snapshot.data != null).toString()),
                      if (snapshot.data != null) ...[
                        _buildDebugInfoRow("Stored Image Length",
                            "${snapshot.data!.length} chars"),
                        FutureBuilder<bool>(
                          future: _testBase64Validity(snapshot.data!),
                          builder: (context, validitySnapshot) {
                            return _buildDebugInfoRow("Valid Base64",
                                validitySnapshot.data?.toString() ?? "Checking...");
                          },
                        ),
                      ],
                    ],
                  );
                },
              ),
              FutureBuilder<String?>(
                future: SharedPreferences.getInstance().then(
                        (prefs) => prefs.getString('employee_face_features_${widget.employeeId}')
                ),
                builder: (context, snapshot) {
                  return _buildDebugInfoRow("Stored Face Features",
                      (snapshot.data != null && snapshot.data!.isNotEmpty).toString());
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text("Close"),
          ),
          if (_image != null && (_image!.contains('data:image') && _image!.contains(',')))
            TextButton(
              onPressed: () {
                setState(() {
                  _image = _image!.split(',')[1];
                  _debugStatus = "Image format fixed!";
                });
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Image format fixed!"))
                );
                _showDebugInfo();
              },
              child: const Text("Fix Image Format"),
            ),
        ],
      ),
    );
  }

  Future<bool> _testBase64Validity(String data) async {
    try {
      if (data.contains('data:image') && data.contains(',')) {
        String base64Part = data.split(',')[1];
        base64Decode(base64Part);
        return true; // Data URL format but base64 part is valid
      } else {
        base64Decode(data);
        return true; // Pure base64 and valid
      }
    } catch (e) {
      return false; // Invalid base64
    }
  }

  Widget _buildDebugInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              "$label:",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}