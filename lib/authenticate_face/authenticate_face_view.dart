// lib/authenticate_face/authenticate_face_view.dart

import 'dart:convert';
import 'dart:developer';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/authenticate_face/scanning_animation/animated_view.dart';
import 'package:face_auth_compatible/authenticate_face/user_password_setup_view.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

class AuthenticateFaceView extends StatefulWidget {
  final String? employeeId; // Made optional for backward compatibility
  final String? employeePin; // Made optional for backward compatibility
  final bool isRegistrationValidation;
  final Function(bool success)? onAuthenticationComplete; // Add callback for check-in process

  const AuthenticateFaceView({
    Key? key,
    this.employeeId,
    this.employeePin,
    this.isRegistrationValidation = false,
    this.onAuthenticationComplete,
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
  String _similarity = "0.0";
  bool _canAuthenticate = false;
  Map<String, dynamic>? employeeData;
  bool isMatching = false;
  int trialNumber = 1;
  bool _isOfflineMode = false;

  // Debug information
  bool _hasStoredFace = false;
  int _storedImageSize = 0;
  String _lastSimilarityScore = "0.0";
  String _lastThresholdUsed = "0.0";
  String _lastAuthResult = "Not attempted";
  bool _isLoading = false;
  String _debugStatus = "Not started";

  @override
  void initState() {
    super.initState();
    // Check if we're in offline mode
    _checkConnectivity();

    // Check for stored face image
    if (widget.employeeId != null) {
      _checkStoredImage();
    }

    // If employeeId is provided, fetch that specific employee data
    if (widget.employeeId != null) {
      _fetchEmployeeData(widget.employeeId!);
    }
  }

  Future<void> _checkStoredImage() async {
    try {
      if (widget.employeeId == null) return;

      final prefs = await SharedPreferences.getInstance();
      String? storedImage = prefs.getString('employee_image_${widget.employeeId}');

      setState(() {
        _hasStoredFace = storedImage != null && storedImage.isNotEmpty;
        _storedImageSize = storedImage?.length ?? 0;
      });

      debugPrint("Stored face check: exists=${_hasStoredFace}, size=${_storedImageSize} bytes");
    } catch (e) {
      debugPrint("Error checking stored image: $e");
    }
  }

  Future<void> _checkConnectivity() async {
    // This is a simplified check - in a real app you would use
    // the ConnectivityService from your service_locator.dart
    try {
      await FirebaseFirestore.instance.collection('test').doc('test').get()
          .timeout(const Duration(seconds: 5));
      setState(() {
        _isOfflineMode = false;
      });
    } catch (e) {
      setState(() {
        _isOfflineMode = true;
      });
      debugPrint("Operating in offline mode");
    }
  }

  Future<void> _fetchEmployeeData(String employeeId) async {
    try {
      // First try to get from local storage
      Map<String, dynamic>? localData = await _getUserDataLocally(employeeId);

      if (localData != null) {
        setState(() {
          employeeData = localData;
          // Show local data immediately
          _isLoading = false;
        });

        // If offline, stop here - we've shown cached data
        if (_isOfflineMode) {
          debugPrint("Using cached employee data in offline mode");
          return;
        }
      }

      // If online, try to get fresh data from Firestore
      if (!_isOfflineMode) {
        DocumentSnapshot snapshot = await FirebaseFirestore.instance
            .collection('employees')
            .doc(employeeId)
            .get();

        if (snapshot.exists) {
          Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

          // Save the data locally for future offline access
          await _saveUserDataLocally(employeeId, data);

          // Also save the face image separately if it exists
          if (data.containsKey('image') && data['image'] != null) {
            await _saveEmployeeImageLocally(employeeId, data['image']);
            _checkStoredImage(); // Update stored image status
          }

          setState(() {
            employeeData = data;
          });

          debugPrint("Fetched and cached employee data from Firestore");
        } else {
          CustomSnackBar.errorSnackBar("Employee data not found");
        }
      }
    } catch (e) {
      debugPrint("Error fetching employee data: $e");
      // Try to get from local storage as fallback
      Map<String, dynamic>? localData = await _getUserDataLocally(employeeId);
      if (localData != null) {
        setState(() {
          employeeData = localData;
        });
        debugPrint("Retrieved employee data from local storage after error");
      } else {
        CustomSnackBar.errorSnackBar("Error: $e");
      }
    }
  }

  // Save user data locally
  Future<void> _saveUserDataLocally(String userId, Map<String, dynamic> userData) async {
    try {
      // Store complete user details in SharedPreferences
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // Create a deep copy of the data that we can modify
      Map<String, dynamic> dataCopy = Map<String, dynamic>.from(userData);

      // Convert all Timestamp objects to ISO8601 strings
      dataCopy.forEach((key, value) {
        if (value is Timestamp) {
          dataCopy[key] = value.toDate().toIso8601String();
        }
      });

      // Save the full userData JSON
      await prefs.setString('user_data_$userId', jsonEncode(dataCopy));

      // Also save critical fields individually for faster access and recovery
      await prefs.setString('user_name_$userId', userData['name'] ?? 'User');
      await prefs.setString('user_designation_$userId', userData['designation'] ?? '');
      await prefs.setString('user_department_$userId', userData['department'] ?? '');

      // If image exists, save it separately (it can be large)
      if (userData.containsKey('image') && userData['image'] != null) {
        await prefs.setString('user_image_$userId', userData['image']);
        // Remove image from the main data to avoid duplication
        Map<String, dynamic> dataWithoutImage = Map<String, dynamic>.from(userData);
        dataWithoutImage.remove('image');
        await prefs.setString('user_data_no_image_$userId', jsonEncode(dataWithoutImage));
      }

      debugPrint("Saved comprehensive user data locally for ID: $userId");
    } catch (e) {
      debugPrint('Error saving user data locally: $e');
    }
  }

  // Get locally stored user data
  Future<Map<String, dynamic>?> _getUserDataLocally(String userId) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      // Try to get complete data first
      String? completeUserData = prefs.getString('user_data_$userId');
      if (completeUserData != null) {
        debugPrint("Retrieved complete local user data for ID: $userId");
        return jsonDecode(completeUserData) as Map<String, dynamic>;
      }

      // If complete data is missing, try to reconstruct from individual fields
      String? userName = prefs.getString('user_name_$userId');
      if (userName != null) {
        debugPrint("Reconstructing user data from individual fields for ID: $userId");
        Map<String, dynamic> reconstructedData = {
          'name': userName,
          'designation': prefs.getString('user_designation_$userId') ?? '',
          'department': prefs.getString('user_department_$userId') ?? '',
        };

        // Try to get image separately
        String? userImage = prefs.getString('user_image_$userId');
        if (userImage != null) {
          reconstructedData['image'] = userImage;
        }

        return reconstructedData;
      }

      debugPrint("No local user data found for ID: $userId");
      return null;
    } catch (e) {
      debugPrint('Error getting user data locally: $e');
      return null;
    }
  }

  // Save employee image for offline face auth
  Future<void> _saveEmployeeImageLocally(String employeeId, String imageBase64) async {
    try {
      // Clean the image data before storing
      String cleanedImage = imageBase64;

      // If the image is in data URL format, extract just the base64 part
      if (cleanedImage.contains('data:image') && cleanedImage.contains(',')) {
        cleanedImage = cleanedImage.split(',')[1];
        debugPrint("Cleaned data URL format to pure base64");
      }

      // Store the cleaned image
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('employee_image_$employeeId', cleanedImage);
      debugPrint("Saved employee image (length: ${cleanedImage.length})");

      // Update debug info
      setState(() {
        _hasStoredFace = true;
        _storedImageSize = cleanedImage.length;
      });
    } catch (e) {
      debugPrint("Error saving employee image: $e");
    }
  }

  // Get locally stored employee image
  Future<String?> _getEmployeeImageLocally(String employeeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? imageData = prefs.getString('employee_image_$employeeId');
      if (imageData != null) {
        debugPrint("Retrieved local employee image for ID: $employeeId");
      } else {
        debugPrint("No local employee image found for ID: $employeeId");
      }
      return imageData;
    } catch (e) {
      debugPrint("Error getting employee image locally: $e");
      return null;
    }
  }

  // Check if face is detected in the camera image
  Future<bool> _verifyFaceDetected() async {
    if (image2.bitmap == null || image2.bitmap!.isEmpty) {
      debugPrint("No camera image available for face detection");
      return false;
    }

    // Since we already have _faceFeatures from the FaceDetector in Google ML Kit,
    // we can use it to determine if a face was detected
    bool hasFace = _faceFeatures != null;

    debugPrint("Face detection result: ${hasFace ? 'Face detected' : 'No face detected'}");

    return hasFace;
  }

  // Authentication initiation
  void _startAuthentication() async {
    setState(() => isMatching = true);
    _playScanningAudio;

    // First check if a face is detected in the camera image
    bool hasFace = await _verifyFaceDetected();
    if (!hasFace) {
      _audioPlayer.stop();
      CustomSnackBar.errorSnackBar("No face detected in camera image. Please try again.");
      setState(() => isMatching = false);
      return;
    }

    if (_isOfflineMode) {
      _handleOfflineAuthentication();
    } else if (widget.employeeId != null) {
      _matchFaceWithStored();
    } else {
      _promptForPin();
    }
  }

  @override
  void dispose() {
    _faceDetector.close();
    _audioPlayer.dispose();
    _pinController.dispose();
    super.dispose();
  }

  AudioPlayer get _playScanningAudio => _audioPlayer
    ..setReleaseMode(ReleaseMode.loop)
    ..play(AssetSource("scan_beep.wav"));

  AudioPlayer get _playFailedAudio => _audioPlayer
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
        actions: [
          // Add debug button
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.white),
            onPressed: _showDebugConsole,
            tooltip: 'Debug Console',
          ),
        ],
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
                        child: const Text(
                          "Let's verify your face was registered correctly",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (_isOfflineMode)
                      Padding(
                        padding: EdgeInsets.only(bottom: 0.01.sh),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.offline_bolt, color: Colors.orange, size: 20),
                              SizedBox(width: 8),
                              Text(
                                "Offline Mode - Using cached data",
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
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
                              onTap: _startAuthentication,
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

  Future<void> _setImage(Uint8List imageToAuthenticate) async {
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
      barrierDismissible: false,
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
      if (!_isOfflineMode) {
        // Online mode - query Firestore
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

        // Get the employee document and ID
        final DocumentSnapshot employeeDoc = snapshot.docs.first;
        final String employeeId = employeeDoc.id;
        final Map<String, dynamic> data = employeeDoc.data() as Map<String, dynamic>;

        // Save for offline use
        await _saveUserDataLocally(employeeId, data);
        if (data.containsKey('image') && data['image'] != null) {
          await _saveEmployeeImageLocally(employeeId, data['image']);
        }

        // Set the employee data
        setState(() {
          employeeData = data;
        });

        // Proceed with face matching
        _matchFaceWithStored();
      } else {
        // Offline mode - we need to scan local storage for matching PIN
        // This is a simplified approach - a proper implementation would use a local database
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        Set<String> keys = prefs.getKeys();

        String? matchedEmployeeId;
        Map<String, dynamic>? matchedData;

        // Look for user data entries
        for (String key in keys) {
          if (key.startsWith('user_data_')) {
            String? userData = prefs.getString(key);
            if (userData != null) {
              Map<String, dynamic> data = jsonDecode(userData) as Map<String, dynamic>;
              if (data['pin'] == pin) {
                matchedEmployeeId = key.replaceFirst('user_data_', '');
                matchedData = data;
                break;
              }
            }
          }
        }

        if (matchedEmployeeId == null || matchedData == null) {
          setState(() => isMatching = false);
          _playFailedAudio;
          CustomSnackBar.errorSnackBar("Invalid PIN or no cached data available");
          return;
        }

        // Set the employee data
        setState(() {
          employeeData = matchedData;
        });

        // Proceed with face matching
        _matchFaceWithStored();
      }
    } catch (e) {
      debugPrint("Error in _fetchEmployeeByPin: $e");
      setState(() => isMatching = false);
      _playFailedAudio;
      CustomSnackBar.errorSnackBar("Error verifying PIN: $e");
    }
  }

  Future<void> _matchFaceWithStored() async {
    debugPrint("Starting face matching process...");
    debugPrint("Offline mode: $_isOfflineMode");

    // Variables to store authentication data
    String? storedImage;
    bool hasImageData = false;

    try {
      // First try to get stored image from local storage
      if (widget.employeeId != null) {
        final prefs = await SharedPreferences.getInstance();
        storedImage = prefs.getString('employee_image_${widget.employeeId}');

        if (storedImage != null && storedImage.isNotEmpty) {
          debugPrint("Found locally stored image for ${widget.employeeId}, length: ${storedImage.length}");
          hasImageData = true;

          // Clean the image format if needed
          if (storedImage.contains('data:image') && storedImage.contains(',')) {
            storedImage = storedImage.split(',')[1];
            debugPrint("Cleaned data URL format to pure base64");
          }

          // Update debug info
          setState(() {
            _hasStoredFace = true;
            _storedImageSize = storedImage!.length;
            _lastThresholdUsed = _isOfflineMode ? "75.0" : "90.0";
          });
        } else {
          debugPrint("No local image found for ${widget.employeeId}");
        }
      }

      // If still no image data, try to get from employeeData as fallback
      if (!hasImageData && employeeData != null) {
        if (employeeData!.containsKey('image') && employeeData!['image'] != null) {
          storedImage = employeeData!['image'];

          // Clean the image format if needed
          if (storedImage!.contains('data:image') && storedImage!.contains(',')) {
            storedImage = storedImage!.split(',')[1];
            debugPrint("Cleaned data URL format from employeeData");
          }

          debugPrint("Using image from employeeData, length: ${storedImage?.length ?? 'null'}");
          hasImageData = true;

          // Update debug info
          setState(() {
            _hasStoredFace = true;
            _storedImageSize = storedImage!.length;
            _lastThresholdUsed = _isOfflineMode ? "75.0" : "90.0";
          });
        }
      }

      // If we still don't have image data, show failure
      if (!hasImageData || storedImage == null) {
        debugPrint("No face image found for authentication");
        setState(() {
          _lastAuthResult = "Failed - No stored image";
          isMatching = false;
        });
        _playFailedAudio;
        _showFailureDialog(
          title: "Authentication Error",
          description: "No registered face found for this employee. Please ensure face registration is complete or try again when online.",
        );

        if (widget.onAuthenticationComplete != null) {
          widget.onAuthenticationComplete!(false);
        }
        return;
      }

      // Verify we can decode the base64 string
      try {
        final bytes = base64Decode(storedImage);
        debugPrint("Successfully decoded base64 image: ${bytes.length} bytes");
      } catch (e) {
        debugPrint("Error decoding base64 image: $e");
        setState(() {
          _lastAuthResult = "Failed - Invalid base64";
          isMatching = false;
        });
        _playFailedAudio;
        _showFailureDialog(
          title: "Authentication Error",
          description: "Stored face image is corrupted. Please register your face again.",
        );

        if (widget.onAuthenticationComplete != null) {
          widget.onAuthenticationComplete!(false);
        }
        return;
      }

      // Set up Regula face comparison
      image1.bitmap = storedImage;
      image1.imageType = regula.ImageType.PRINTED;

      debugPrint("Starting face comparison with Regula SDK");
      debugPrint("Image1 (stored image) length: ${storedImage.length}");
      debugPrint("Image2 (camera image) bitmap length: ${image2.bitmap?.length ?? 'null'}");

      var request = regula.MatchFacesRequest();
      request.images = [image1, image2];

      // IMPORTANT: Ensure the Regula SDK processes correctly locally
      dynamic value = await regula.FaceSDK.matchFaces(jsonEncode(request));
      debugPrint("Face SDK returned value");

      var response = regula.MatchFacesResponse.fromJson(json.decode(value));

      if (response == null || response.results == null || response.results!.isEmpty) {
        debugPrint("No matching results returned from SDK");
        setState(() {
          isMatching = false;
          _lastAuthResult = "Failed - No results from SDK";
        });
        _playFailedAudio;
        _showFailureDialog(
          title: "Authentication Failed",
          description: "Unable to process face comparison. Please try again with better lighting.",
        );

        if (widget.onAuthenticationComplete != null) {
          widget.onAuthenticationComplete!(false);
        }
        return;
      }

      // Use different threshold values for online vs offline
      double thresholdValue = _isOfflineMode ? 0.5 : 0.75;

      dynamic str = await regula.FaceSDK.matchFacesSimilarityThresholdSplit(
          jsonEncode(response.results), thresholdValue);

      var split = regula.MatchFacesSimilarityThresholdSplit.fromJson(json.decode(str));

      // Use a slightly lower threshold in offline mode, but not TOO low
      double similarityThreshold = _isOfflineMode ? 75.0 : 90.0;

      setState(() {
        _similarity = split!.matchedFaces.isNotEmpty
            ? (split.matchedFaces[0]!.similarity! * 100).toStringAsFixed(2)
            : "0.0";
        _lastSimilarityScore = _similarity;
        debugPrint("Face similarity score: $_similarity%");
      });

      // Check if faces match
      if (_similarity != "0.0" && double.parse(_similarity) > similarityThreshold) {
        debugPrint("Face authentication successful! Similarity: $_similarity%");
        setState(() {
          _lastAuthResult = "Success ($_similarity%)";
        });
        _handleSuccessfulAuthentication();
      } else {
        // Face doesn't match
        debugPrint("Face authentication failed! Similarity: $_similarity%");
        setState(() {
          _lastAuthResult = "Failed - Low similarity ($_similarity%)";
          isMatching = false;
        });
        _playFailedAudio;
        _showFailureDialog(
          title: "Authentication Failed",
          description: "Face doesn't match. Please try again.",
        );

        if (widget.onAuthenticationComplete != null) {
          widget.onAuthenticationComplete!(false);
        }
      }
    } catch (e) {
      debugPrint("Error during face matching: $e");
      setState(() {
        isMatching = false;
        _lastAuthResult = "Failed - Error: $e";
      });
      _playFailedAudio;
      _showFailureDialog(
        title: "Authentication Error",
        description: "Error during face matching: $e",
      );

      if (widget.onAuthenticationComplete != null) {
        widget.onAuthenticationComplete!(false);
      }
    }
  }

  Future<void> _handleOfflineAuthentication() async {
    debugPrint("Starting offline authentication with ML Kit");

    try {
      // First check if we have a face detected
      if (_faceFeatures == null) {
        debugPrint("No face features detected for offline authentication");
        setState(() => isMatching = false);
        _playFailedAudio;
        _showFailureDialog(
          title: "Authentication Failed",
          description: "No face detected. Please try again with better lighting.",
        );
        if (widget.onAuthenticationComplete != null) {
          widget.onAuthenticationComplete!(false);
        }
        return;
      }

      // Get stored face features
      final prefs = await SharedPreferences.getInstance();
      String? storedFeaturesJson = prefs.getString('employee_face_features_${widget.employeeId}');

      if (storedFeaturesJson == null || storedFeaturesJson.isEmpty) {
        // Fall back to image comparison if no stored features
        await _matchFaceWithStored();
        return;
      }

      // Parse stored features
      // Parse stored features
      Map<String, dynamic> storedFeaturesMap = json.decode(storedFeaturesJson);
      FaceFeatures storedFeatures = FaceFeatures.fromJson(storedFeaturesMap);

      // Compare key facial features
      bool hasMatchingLeftEye = _comparePoints(storedFeatures.leftEye, _faceFeatures!.leftEye, 50);
      bool hasMatchingRightEye = _comparePoints(storedFeatures.rightEye, _faceFeatures!.rightEye, 50);
      bool hasMatchingNose = _comparePoints(storedFeatures.noseBase, _faceFeatures!.noseBase, 50);
      bool hasMatchingMouth = _comparePoints(storedFeatures.leftMouth, _faceFeatures!.leftMouth, 50) &&
          _comparePoints(storedFeatures.rightMouth, _faceFeatures!.rightMouth, 50);

      // Calculate match percentage
      int matchCount = 0;
      int totalTests = 4;

      if (hasMatchingLeftEye) matchCount++;
      if (hasMatchingRightEye) matchCount++;
      if (hasMatchingNose) matchCount++;
      if (hasMatchingMouth) matchCount++;

      double matchPercentage = matchCount / totalTests * 100;

      setState(() {
        _similarity = matchPercentage.toStringAsFixed(2);
        _lastSimilarityScore = _similarity;
        _lastThresholdUsed = "75.0"; // We use 75% match threshold for offline
      });

      debugPrint("Offline face match: $matchPercentage% ($matchCount/$totalTests features matched)");

      // Determine if match is successful
      if (matchPercentage >= 75.0) { // 75% match threshold
        debugPrint("Offline authentication successful!");
        setState(() {
          _lastAuthResult = "Success ($_similarity%)";
        });
        _handleSuccessfulAuthentication();
      } else {
        debugPrint("Offline authentication failed!");
        setState(() {
          _lastAuthResult = "Failed - Low similarity ($_similarity%)";
          isMatching = false;
        });
        _playFailedAudio;
        _showFailureDialog(
          title: "Authentication Failed",
          description: "Face doesn't match. Please try again.",
        );

        if (widget.onAuthenticationComplete != null) {
          widget.onAuthenticationComplete!(false);
        }
      }
    } catch (e) {
      debugPrint("Error in offline face matching: $e");

      // Fall back to original method if our ML Kit approach fails
      try {
        await _matchFaceWithStored();
      } catch (fallbackError) {
        setState(() => isMatching = false);
        _playFailedAudio;
        _showFailureDialog(
          title: "Authentication Failed",
          description: "Error during face matching: $e",
        );

        if (widget.onAuthenticationComplete != null) {
          widget.onAuthenticationComplete!(false);
        }
      }
    }
  }

  // Helper method to compare two facial points with tolerance
  bool _comparePoints(Points? p1, Points? p2, double tolerance) {
    if (p1 == null || p2 == null || p1.x == null || p2.x == null) return false;

    double distance = sqrt(
        (p1.x! - p2.x!) * (p1.x! - p2.x!) +
            (p1.y! - p2.y!) * (p1.y! - p2.y!)
    );

    return distance <= tolerance;
  }

  // Helper method for successful authentication
  void _handleSuccessfulAuthentication() {
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
      // If this is a regular authentication (like for check-in)
      _showSuccessDialog();

      // Call the callback if provided (for check-in process)
      if (widget.onAuthenticationComplete != null) {
        widget.onAuthenticationComplete!(true);
      }
    }
  }

  void _showSuccessDialog() {
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
              // The dashboard will handle navigation
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

  void _showFailureDialog({
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

  // Add the debug console method here
  void _showDebugConsole() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Face Authentication Debug"),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDebugSection("Connectivity", [
                  "Status: ${_isOfflineMode ? 'Offline' : 'Online'}",
                ]),
                const SizedBox(height: 10),
                _buildDebugSection("Local Storage", [
                  "Employee ID: ${widget.employeeId ?? 'Not provided'}",
                  "Has Stored Face: $_hasStoredFace",
                  "Image Size: $_storedImageSize bytes",
                ]),
                const SizedBox(height: 10),
                _buildDebugSection("Last Authentication", [
                  "Similarity Score: $_lastSimilarityScore%",
                  "Threshold Used: $_lastThresholdUsed%",
                  "Result: $_lastAuthResult",
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close"),
            ),
            ElevatedButton(
              onPressed: _fixStoredImage,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
              ),
              child: const Text("Fix Stored Image"),
            ),
            ElevatedButton(
              onPressed: _resetAuthenticationState,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text("Reset Authentication"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDebugSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 5),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(left: 10, top: 3),
          child: Text("• $item"),
        )),
      ],
    );
  }

  Future<void> _fixStoredImage() async {
    try {
      if (widget.employeeId == null) {
        CustomSnackBar.errorSnackBar("No employee ID provided");
        return;
      }

      setState(() => _isLoading = true);

      final prefs = await SharedPreferences.getInstance();
      String? storedImage = prefs.getString('employee_image_${widget.employeeId}');

      if (storedImage == null || storedImage.isEmpty) {
        setState(() => _isLoading = false);
        CustomSnackBar.errorSnackBar("No image found to fix");
        return;
      }

      // First check if it's in data URL format
      bool wasFixed = false;
      String cleanedImage = storedImage;

      if (cleanedImage.contains('data:image') && cleanedImage.contains(',')) {
        cleanedImage = cleanedImage.split(',')[1];
        wasFixed = true;
      }

      // Then verify it's actually valid base64
      try {
        base64Decode(cleanedImage);
      } catch (e) {
        setState(() => _isLoading = false);
        CustomSnackBar.errorSnackBar("Image is not valid base64 and cannot be fixed automatically");
        return;
      }

      // Save the fixed image
      await prefs.setString('employee_image_${widget.employeeId}', cleanedImage);

      setState(() {
        _isLoading = false;
        _storedImageSize = cleanedImage.length;
        _hasStoredFace = true;
      });

      if (wasFixed) {
        CustomSnackBar.successSnackBar("Image fixed! Try authentication again");
      } else {
        CustomSnackBar.successSnackBar("Image was already in correct format");
      }

      // Close the dialog
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar("Error fixing image: $e");
    }
  }

  Future<void> _resetAuthenticationState() async {
    setState(() {
      _similarity = "0.0";
      _lastSimilarityScore = "0.0";
      _lastAuthResult = "Reset";
      isMatching = false;
      _canAuthenticate = false;
    });

    // Reset camera image
    image2 = regula.MatchFacesImage();

    CustomSnackBar.successSnackBar("Authentication state reset");

    // Close the dialog
    Navigator.of(context).pop();
  }
}