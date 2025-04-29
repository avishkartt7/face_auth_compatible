// lib/dashboard/check_in_out_view.dart

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/common/utils/extensions/size_extension.dart';
import 'package:face_auth_compatible/common/utils/extract_face_feature.dart';
import 'package:face_auth_compatible/common/views/camera_view.dart';
import 'package:face_auth_compatible/common/views/custom_button.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_face_api/face_api.dart' as regula;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';

class CheckInOutView extends StatefulWidget {
  final String employeeId;
  final bool isCheckIn;
  final VoidCallback onComplete;

  const CheckInOutView({
    Key? key,
    required this.employeeId,
    required this.isCheckIn,
    required this.onComplete,
  }) : super(key: key);

  @override
  State<CheckInOutView> createState() => _CheckInOutViewState();
}

class _CheckInOutViewState extends State<CheckInOutView> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  var image1 = regula.MatchFacesImage();
  var image2 = regula.MatchFacesImage();

  bool _canVerify = false;
  bool _isVerifying = false;
  Map<String, dynamic>? employeeData;
  String _similarity = "";
  String? _attendanceId;

  @override
  void initState() {
    super.initState();
    _fetchEmployeeData();
    if (!widget.isCheckIn) {
      _fetchTodayAttendance();
    }
  }

  Future<void> _fetchEmployeeData() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
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

  Future<void> _fetchTodayAttendance() async {
    try {
      // Get today's date at midnight
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Query Firestore for today's attendance records
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .where('employeeId', isEqualTo: widget.employeeId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
          .orderBy('date', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        setState(() {
          _attendanceId = snapshot.docs.first.id;
        });
      }
    } catch (e) {
      CustomSnackBar.errorSnackBar("Error checking attendance: $e");
    }
  }

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
        title: Text(widget.isCheckIn ? "Check In" : "Check Out"),
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
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 0.1.sw),
              child: Text(
                widget.isCheckIn
                    ? "Please verify your face to check in"
                    : "Please verify your face to check out",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 0.02.sh),
            Container(
              height: 0.75.sh,
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
                children: [
                  Text(
                    DateFormat("EEEE, MMMM d, yyyy").format(DateTime.now()),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    DateFormat("h:mm a").format(DateTime.now()),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 0.02.sh),
                  CameraView(
                    onImage: (image) {
                      _setImage(image);
                    },
                    onInputImage: (inputImage) async {
                      // Process input image but don't need to extract features
                    },
                  ),
                  const Spacer(),
                  if (_isVerifying)
                    const CircularProgressIndicator(color: accentColor)
                  else if (_canVerify)
                    CustomButton(
                      text: widget.isCheckIn ? "Check In" : "Check Out",
                      onTap: _verifyFaceAndProcess,
                    ),
                  SizedBox(height: 0.02.sh),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future _setImage(Uint8List imageToVerify) async {
    image2.bitmap = base64Encode(imageToVerify);
    image2.imageType = regula.ImageType.PRINTED;

    setState(() {
      _canVerify = true;
    });
  }

  Future<void> _verifyFaceAndProcess() async {
    if (employeeData == null || !employeeData!.containsKey('image')) {
      CustomSnackBar.errorSnackBar("No registered face found for this employee");
      return;
    }

    setState(() => _isVerifying = true);

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
      });

      // Check if faces match
      if (_similarity != "error" && double.parse(_similarity) > 85.00) {
        // Face verification successful, process check-in/out
        if (widget.isCheckIn) {
          await _processCheckIn();
        } else {
          await _processCheckOut();
        }
      } else {
        // Face doesn't match
        setState(() => _isVerifying = false);
        _showFailureDialog(
          title: "Verification Failed",
          description: "Face doesn't match. Please try again.",
        );
      }
    } catch (e) {
      setState(() => _isVerifying = false);
      CustomSnackBar.errorSnackBar("Error during face verification: $e");
    }
  }

  Future<void> _processCheckIn() async {
    try {
      // Create a new attendance record
      final now = DateTime.now();
      final todayDate = DateTime(now.year, now.month, now.day);

      final DocumentReference docRef = await FirebaseFirestore.instance
          .collection('attendance')
          .add({
        'employeeId': widget.employeeId,
        'date': Timestamp.fromDate(todayDate),
        'checkInTime': Timestamp.fromDate(now),
        'checkOutTime': null,
        'status': 'checked-in',
      });

      setState(() => _isVerifying = false);

      // Show success dialog
      _showSuccessDialog(
        widget.isCheckIn ? "Check In Successful" : "Check Out Successful",
        "You have successfully checked in at ${DateFormat('h:mm a').format(now)}",
      );
    } catch (e) {
      setState(() => _isVerifying = false);
      CustomSnackBar.errorSnackBar("Error processing check-in: $e");
    }
  }

  Future<void> _processCheckOut() async {
    try {
      if (_attendanceId == null) {
        setState(() => _isVerifying = false);
        CustomSnackBar.errorSnackBar("No check-in record found for today");
        return;
      }

      // Update the existing attendance record
      final now = DateTime.now();

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(_attendanceId)
          .update({
        'checkOutTime': Timestamp.fromDate(now),
        'status': 'checked-out',
      });

      setState(() => _isVerifying = false);

      // Show success dialog
      _showSuccessDialog(
        "Check Out Successful",
        "You have successfully checked out at ${DateFormat('h:mm a').format(now)}",
      );
    } catch (e) {
      setState(() => _isVerifying = false);
      CustomSnackBar.errorSnackBar("Error processing check-out: $e");
    }
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back to dashboard
              widget.onComplete(); // Trigger callback to refresh dashboard
            },
            child: const Text(
              "Done",
              style: TextStyle(color: accentColor),
            ),
          ),
        ],
      ),
    );
  }

  void _showFailureDialog({
    required String title,
    required String description,
  }) {
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