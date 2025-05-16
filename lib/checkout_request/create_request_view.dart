// lib/checkout_request/create_request_view.dart - Updated version

import 'package:flutter/material.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/model/check_out_request_model.dart';
import 'package:face_auth_compatible/repositories/check_out_request_repository.dart';
import 'package:face_auth_compatible/services/service_locator.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CreateCheckOutRequestView extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final Position currentPosition;
  final VoidCallback? onRequestSubmitted;
  // Added new field for passing extra data without changing constructor
  final Map<String, dynamic>? extra;

  const CreateCheckOutRequestView({
    Key? key,
    required this.employeeId,
    required this.employeeName,
    required this.currentPosition,
    this.onRequestSubmitted,
    this.extra,
  }) : super(key: key);

  @override
  State<CreateCheckOutRequestView> createState() => _CreateCheckOutRequestViewState();
}

class _CreateCheckOutRequestViewState extends State<CreateCheckOutRequestView> {
  final TextEditingController _reasonController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  String _locationName = "Fetching location...";
  String _lineManagerName = "Unknown";
  String? _lineManagerId;
  bool _isCheckIn = false; // Default to check-out

  @override
  void initState() {
    super.initState();
    _getLocationName();

    // Extract parameters from extra map if available
    if (widget.extra != null) {
      _lineManagerId = widget.extra!['lineManagerId'];
      _isCheckIn = widget.extra!['isCheckIn'] ?? false;
    }

    // Get manager info based on lineManagerId
    if (_lineManagerId != null) {
      _getLineManagerInfo(_lineManagerId!);
    } else {
      // If no lineManagerId provided, try to find one
      _findLineManager();
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  // Get human-readable location name from coordinates
  Future<void> _getLocationName() async {
    try {
      // Get the address from coordinates
      List<Placemark> placemarks = await placemarkFromCoordinates(
          widget.currentPosition.latitude,
          widget.currentPosition.longitude
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        // Format the address
        setState(() {
          _locationName = "${place.street}, ${place.locality}, ${place.country}";
        });
      }
    } catch (e) {
      setState(() {
        _locationName = "Unknown location";
      });
      print("Error getting location name: $e");
    }
  }

  // Find line manager if not provided
  Future<void> _findLineManager() async {
    try {
      // First try to get from shared preferences (faster)
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? savedManagerId = prefs.getString('line_manager_id_${widget.employeeId}');
      String? savedManagerName = prefs.getString('line_manager_name_${widget.employeeId}');

      if (savedManagerId != null && savedManagerName != null) {
        setState(() {
          _lineManagerId = savedManagerId;
          _lineManagerName = savedManagerName;
        });
        return;
      }

      // If not in preferences, try to get from Firestore
      // First check employee document for managerInformation
      final employeeDoc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .get();

      if (employeeDoc.exists) {
        Map<String, dynamic> data = employeeDoc.data() as Map<String, dynamic>;

        if (data.containsKey('lineManagerId') && data['lineManagerId'] != null) {
          // Get manager name from their employee document
          final managerDoc = await FirebaseFirestore.instance
              .collection('employees')
              .doc(data['lineManagerId'])
              .get();

          if (managerDoc.exists) {
            setState(() {
              _lineManagerId = data['lineManagerId'];
              _lineManagerName = managerDoc.data()?['name'] ?? "Unknown Manager";
            });

            // Save for next time
            await prefs.setString('line_manager_id_${widget.employeeId}', _lineManagerId!);
            await prefs.setString('line_manager_name_${widget.employeeId}', _lineManagerName);
            return;
          }
        }
      }

      // If not found in employee document, check line_managers collection
      final lineManagersSnapshot = await FirebaseFirestore.instance
          .collection('line_managers')
          .where('teamMembers', arrayContains: widget.employeeId)
          .limit(1)
          .get();

      if (lineManagersSnapshot.docs.isNotEmpty) {
        final managerData = lineManagersSnapshot.docs[0].data();
        final managerId = managerData['managerId'];

        // Get manager name
        final managerDoc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(managerId)
            .get();

        if (managerDoc.exists) {
          setState(() {
            _lineManagerId = managerId;
            _lineManagerName = managerDoc.data()?['name'] ?? "Unknown Manager";
          });

          // Save for next time
          await prefs.setString('line_manager_id_${widget.employeeId}', _lineManagerId!);
          await prefs.setString('line_manager_name_${widget.employeeId}', _lineManagerName);
          return;
        }
      }

      // If still not found, try to find any manager
      final managerQuery = await FirebaseFirestore.instance
          .collection('employees')
          .where('isManager', isEqualTo: true)
          .limit(1)
          .get();

      if (managerQuery.docs.isNotEmpty) {
        setState(() {
          _lineManagerId = managerQuery.docs[0].id;
          _lineManagerName = managerQuery.docs[0].data()['name'] ?? "Default Manager";
        });
        return;
      }

      // If still not found, set default values
      setState(() {
        _lineManagerId = null;
        _lineManagerName = "No manager assigned";
      });

    } catch (e) {
      print("Error finding line manager: $e");
      setState(() {
        _lineManagerId = null;
        _lineManagerName = "Error finding manager";
      });
    }
  }

  // Get line manager information
  Future<void> _getLineManagerInfo(String managerId) async {
    try {
      // Use the provided lineManagerId to get manager details
      final managerDoc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(managerId)
          .get();

      if (managerDoc.exists) {
        setState(() {
          _lineManagerName = managerDoc.data()?['name'] ?? "Unknown Manager";
        });

        // Save for future use
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('line_manager_id_${widget.employeeId}', managerId);
        await prefs.setString('line_manager_name_${widget.employeeId}', _lineManagerName);
        return;
      }

      // If the ID format is different, try with EMP prefix
      if (!managerId.startsWith('EMP')) {
        final altManagerDoc = await FirebaseFirestore.instance
            .collection('employees')
            .doc('EMP$managerId')
            .get();

        if (altManagerDoc.exists) {
          setState(() {
            _lineManagerName = altManagerDoc.data()?['name'] ?? "Unknown Manager";
          });
          return;
        }
      }

      // If still not found, check if the ID is already with EMP prefix
      if (managerId.startsWith('EMP')) {
        final altManagerDoc = await FirebaseFirestore.instance
            .collection('employees')
            .doc(managerId.substring(3))
            .get();

        if (altManagerDoc.exists) {
          setState(() {
            _lineManagerName = altManagerDoc.data()?['name'] ?? "Unknown Manager";
          });
          return;
        }
      }

      setState(() {
        _lineManagerName = "Manager (ID: $managerId)";
      });
    } catch (e) {
      print("Error getting line manager info: $e");
      setState(() {
        _lineManagerName = "Error finding manager";
      });
    }
  }

  Future<void> _submitRequest() async {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    if (_lineManagerId == null) {
      CustomSnackBar.errorSnackBar("No line manager found. Please contact administrator.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create the request with the appropriate type
      CheckOutRequest request = CheckOutRequest.createNew(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        lineManagerId: _lineManagerId!,
        latitude: widget.currentPosition.latitude,
        longitude: widget.currentPosition.longitude,
        locationName: _locationName,
        reason: _reasonController.text.trim(),
        requestType: _isCheckIn ? 'check-in' : 'check-out',
      );

      // Save the request
      final repository = getIt<CheckOutRequestRepository>();
      bool success = await repository.createCheckOutRequest(request);

      if (success) {
        CustomSnackBar.successSnackBar(
            "${_isCheckIn ? 'Check-in' : 'Check-out'} request submitted successfully"
        );

        // Call the callback if provided
        if (widget.onRequestSubmitted != null) {
          widget.onRequestSubmitted!();
        }

        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        CustomSnackBar.errorSnackBar("Failed to submit request. Please try again.");
      }
    } catch (e) {
      CustomSnackBar.errorSnackBar("Error submitting request: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Request ${_isCheckIn ? 'Check-In' : 'Check-Out'}"),
        backgroundColor: scaffoldTopGradientClr,
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
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "You are outside the office geofence",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "To ${_isCheckIn ? 'check in' : 'check out'} from your current location, you need approval from your line manager.",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Current location
                  const Text(
                    "Current Location",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _locationName,
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Line manager info
                  const Text(
                    "Request Will Be Sent To",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _lineManagerName,
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Reason for action
                  Text(
                    "Reason for ${_isCheckIn ? 'Checking In' : 'Checking Out'}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _reasonController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Please provide a reason...",
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: accentColor),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return "Please provide a reason";
                      }
                      if (value.trim().length < 10) {
                        return "Reason should be at least 10 characters";
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 32),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submitRequest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : Text(
                        "Submit Request",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}