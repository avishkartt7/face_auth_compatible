// lib/authenticate_face/authenticate_face_view.dart

import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;

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
  String _similarity = "";
  bool _canAuthenticate = false;
  Map<String, dynamic>? employeeData;
  bool isMatching = false;
  int trialNumber = 1;
  bool _isOfflineMode = false;

  @override
  void initState() {
    super.initState();
    // Check if we're in offline mode
    _checkConnectivity();

    // If employeeId is provided, fetch that specific employee data
    if (widget.employeeId != null) {
      _fetchEmployeeData(widget.employeeId!);
    }
  }

  Future<void> _checkConnectivity() async {
    // This is a simplified check - in a real app you would use
    // the ConnectivityService from your service_locator.dart
    try {
      await FirebaseFirestore.instance.collection('test').doc('test').get()
          .timeout(const Duration(seconds: 5));
      _isOfflineMode = false;
    } catch (e) {
      _isOfflineMode = true;
      debugPrint("Operating in offline mode");
    }
  }

  Future<void> _fetchEmployeeData(String employeeId) async {
    try {
      if (!_isOfflineMode) {
        // Online mode - try to fetch from Firestore
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(employeeId)
            .get();

        if (doc.exists) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

          // Save the data locally for offline access
          await _saveUserDataLocally(employeeId, data);

          // If has image, save it separately for better offline access
          if (data.containsKey('image') && data['image'] != null) {
            await _saveEmployeeImageLocally(employeeId, data['image']);
          }

          setState(() {
            employeeData = data;
          });

          debugPrint("Fetched and cached employee data from Firestore");
        } else {
          CustomSnackBar.errorSnackBar("Employee data not found");
        }
      } else {
        // Offline mode - try to get data from local storage
        Map<String, dynamic>? localData = await _getUserDataLocally(employeeId);
        if (localData != null) {
          setState(() {
            employeeData = localData;
          });
          debugPrint("Retrieved employee data from local storage");
        } else {
          CustomSnackBar.errorSnackBar("No cached employee data available");
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

      // Save the full userData JSON
      await prefs.setString('user_data_$userId', jsonEncode(userData));

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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('employee_image_$employeeId', imageBase64);
      debugPrint("Saved employee image locally for ID: $employeeId");
    } catch (e) {
      debugPrint("Error saving employee image locally: $e");
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

    // First try to get the image directly from local storage for fastest offline access
    String? storedImage;
    bool hasImageData = false;

    if (widget.employeeId != null) {
      // Always try local storage first in offline mode
      storedImage = await _getEmployeeImageLocally(widget.employeeId!);
      if (storedImage != null) {
        hasImageData = true;
        debugPrint("Using locally stored image from getEmployeeImageLocally()");
      }
    }

    // If not found in local specific storage, check employee data
    if (!hasImageData && employeeData != null) {
      debugPrint("Employee data null? ${employeeData == null}");
      if (employeeData!.containsKey('image') && employeeData!['image'] != null) {
        debugPrint("Image found in employeeData, length: ${employeeData!['image']?.length ?? 'null'}");
        storedImage = employeeData!['image'];
        hasImageData = true;
      }
    }

    // If we still don't have image data, show failure
    if (!hasImageData) {
      debugPrint("No face image found for authentication");
      _showFailureDialog(
        title: "Authentication Error",
        description: "No registered face found for this employee. Please ensure face registration is complete or try again when online.",
      );
      return;
    }

    // Set up the stored face image for comparison
    image1.bitmap = storedImage!;
    image1.imageType = regula.ImageType.PRINTED;

    // Face comparing logic
    var request = regula.MatchFacesRequest();
    request.images = [image1, image2];

    try {
      debugPrint("Starting face matching with Regula SDK");
      dynamic value = await regula.FaceSDK.matchFaces(jsonEncode(request));
      var response = regula.MatchFacesResponse.fromJson(json.decode(value));

      dynamic str = await regula.FaceSDK.matchFacesSimilarityThresholdSplit(
          jsonEncode(response!.results), 0.75);

      var split = regula.MatchFacesSimilarityThresholdSplit.fromJson(json.decode(str));

      setState(() {
        _similarity = split!.matchedFaces.isNotEmpty
            ? (split.matchedFaces[0]!.similarity! * 100).toStringAsFixed(2)
            : "error";
        log("Face similarity: $_similarity");
      });

      // Check if faces match
      if (_similarity != "error" && double.parse(_similarity) > 90.00) {
        debugPrint("Face authentication successful! Similarity: $_similarity");
        _handleSuccessfulAuthentication();
      } else {
        // Face doesn't match
        debugPrint("Face authentication failed! Similarity: $_similarity");
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
      setState(() => isMatching = false);
      _playFailedAudio;
      CustomSnackBar.errorSnackBar("Error during face matching: $e");

      if (widget.onAuthenticationComplete != null) {
        widget.onAuthenticationComplete!(false);
      }
    }
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
}