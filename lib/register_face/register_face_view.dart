// lib/register_face/register_face_view.dart
import 'dart:convert';
import 'dart:typed_data'; // Add this import to fix the error
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
  bool _isRegistering = false;
  bool _isOfflineMode = false;

  // Add debug info variables
  String _debugStatus = "Waiting for face capture";
  String _imageQuality = "Not captured";

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    debugPrint("FACE REG: Initialized RegisterFaceView for employeeId: ${widget.employeeId}");
  }

  Future<void> _checkConnectivity() async {
    try {
      await FirebaseFirestore.instance.collection('test').doc('test').get()
          .timeout(const Duration(seconds: 5));
      setState(() {
        _isOfflineMode = false;
      });
      debugPrint("FACE REG: Online mode detected");
    } catch (e) {
      setState(() {
        _isOfflineMode = true;
      });
      debugPrint("FACE REG: Offline mode detected: $e");
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
            if (_isOfflineMode)
              Container(
                margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.offline_bolt, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "Offline Mode - Face registration may not sync properly",
                      style: TextStyle(
                        color: Colors.orange,
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

      // Proceed with saving to Firestore if online
      if (!_isOfflineMode) {
        debugPrint("FACE REG: Saving to Firestore (online mode)");

        try {
          await FirebaseFirestore.instance
              .collection('employees')
              .doc(widget.employeeId)
              .update({
            'image': cleanedImage, // Store clean base64
            'faceFeatures': _faceFeatures!.toJson(),
            'faceRegistered': true,
          });

          debugPrint("FACE REG: Successfully saved to Firestore");
        } catch (e) {
          debugPrint("FACE REG: Error saving to Firestore: $e");

          // Don't fail entirely on Firestore error, still try to save locally
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Warning: Online sync failed: $e"),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        debugPrint("FACE REG: Skipping Firestore update (offline mode)");
      }

      // Always save locally for offline use
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('employee_image_${widget.employeeId}', cleanedImage);
      debugPrint("FACE REG: Saved face image locally (length: ${cleanedImage.length}) in CLEAN base64 format");

      // Test local storage immediately to verify
      final storedImage = prefs.getString('employee_image_${widget.employeeId}');
      if (storedImage != null) {
        try {
          final bytes = base64Decode(storedImage);
          debugPrint("FACE REG: Local storage verification successful: ${bytes.length} bytes");
        } catch (e) {
          debugPrint("FACE REG: Local storage verification failed: $e");

          // Try one more time with fixed format
          await prefs.setString('employee_image_${widget.employeeId}', cleanedImage);
          debugPrint("FACE REG: Attempted to fix local storage");
        }
      }

      setState(() {
        _isRegistering = false;
        _debugStatus = "Face registered successfully";
      });

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
      setState(() {
        _isRegistering = false;
        _debugStatus = "Error registering face: $e";
      });

      debugPrint("FACE REG: Error registering face: $e");

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error registering face: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
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
            width: 120,
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