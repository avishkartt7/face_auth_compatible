// lib/test/offline_test_view.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:face_auth_compatible/constants/theme.dart';

class OfflineTestView extends StatefulWidget {
  final String employeeId;

  const OfflineTestView({
    Key? key,
    required this.employeeId,
  }) : super(key: key);

  @override
  State<OfflineTestView> createState() => _OfflineTestViewState();
}

class _OfflineTestViewState extends State<OfflineTestView> {
  String _testResult = "No test run yet";
  bool _isLoading = false;
  String? _storedImage;
  int _imageLength = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Offline Authentication Test"),
        backgroundColor: scaffoldTopGradientClr,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Test Face Image Storage",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 20),

            // Test buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _testImageRetrieval,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Test Image Retrieval"),
                ),

                ElevatedButton(
                  onPressed: _isLoading ? null : _checkImageValidity,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Check Image Format"),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Test results
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade100,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Image Status: ${_storedImage != null ? 'Found' : 'Not Found'}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _storedImage != null ? Colors.green : Colors.red,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text("Image Size: $_imageLength bytes"),

                  const SizedBox(height: 16),

                  const Text(
                    "Test Result:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 4),

                  Text(_testResult),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Image preview if available
            if (_storedImage != null && _storedImage!.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Image Preview (first 100 chars):",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 8),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.grey.shade200,
                    ),
                    child: Text(
                      _storedImage!.length > 100
                          ? _storedImage!.substring(0, 100) + "..."
                          : _storedImage!,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: 20),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: _isLoading ? null : _fixImageFormat,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Fix Image Format"),
                ),

                ElevatedButton(
                  onPressed: _isLoading ? null : _clearStoredImage,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Clear Stored Image"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testImageRetrieval() async {
    setState(() {
      _isLoading = true;
      _testResult = "Testing...";
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _storedImage = prefs.getString('employee_image_${widget.employeeId}');

      setState(() {
        _imageLength = _storedImage?.length ?? 0;

        if (_storedImage == null || _storedImage!.isEmpty) {
          _testResult = "No image found in storage for employee ID: ${widget.employeeId}";
        } else {
          _testResult = "Image found in storage with length: $_imageLength bytes";
        }

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _testResult = "Error accessing storage: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _checkImageValidity() async {
    setState(() {
      _isLoading = true;
      _testResult = "Checking image format...";
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _storedImage = prefs.getString('employee_image_${widget.employeeId}');

      if (_storedImage == null || _storedImage!.isEmpty) {
        setState(() {
          _testResult = "No image found to check";
          _isLoading = false;
        });
        return;
      }

      _imageLength = _storedImage!.length;

      // Check if it's base64 encoded
      bool isValidBase64 = false;
      try {
        // Try to decode as base64
        base64Decode(_storedImage!);
        isValidBase64 = true;
      } catch (e) {
        isValidBase64 = false;
      }

      // Check if it's in data URL format
      bool isDataUrl = _storedImage!.startsWith('data:image');

      // Format detection
      String format = "Unknown";
      if (isDataUrl) {
        format = "Data URL format (data:image/...)";
      } else if (_storedImage!.startsWith('/9j/')) {
        format = "Base64 JPEG";
      } else if (_storedImage!.startsWith('iVBOR')) {
        format = "Base64 PNG";
      } else if (isValidBase64) {
        format = "Valid base64, unknown image type";
      } else {
        format = "Not valid base64 or data URL";
      }

      setState(() {
        _testResult = "Image format: $format\nValid base64: $isValidBase64\nIs data URL: $isDataUrl";
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _testResult = "Error checking image: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _fixImageFormat() async {
    setState(() {
      _isLoading = true;
      _testResult = "Attempting to fix image format...";
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _storedImage = prefs.getString('employee_image_${widget.employeeId}');

      if (_storedImage == null || _storedImage!.isEmpty) {
        setState(() {
          _testResult = "No image found to fix";
          _isLoading = false;
        });
        return;
      }

      // Clean the format
      String cleanedImage = _storedImage!;
      bool wasFixed = false;

      // Fix data URL format
      if (cleanedImage.contains('data:image') && cleanedImage.contains(',')) {
        cleanedImage = cleanedImage.split(',')[1];
        wasFixed = true;
      }

      // Try to validate it's base64
      bool isValidBase64 = false;
      try {
        base64Decode(cleanedImage);
        isValidBase64 = true;
      } catch (e) {
        isValidBase64 = false;
      }

      if (isValidBase64) {
        // Save the fixed image
        await prefs.setString('employee_image_${widget.employeeId}', cleanedImage);

        setState(() {
          _storedImage = cleanedImage;
          _imageLength = cleanedImage.length;
          _testResult = wasFixed
              ? "Image fixed! Removed data URL prefix. New length: $_imageLength bytes"
              : "Image was already in correct format. Length: $_imageLength bytes";
        });
      } else {
        setState(() {
          _testResult = "Unable to fix image format. Image is not valid base64.";
        });
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _testResult = "Error fixing image: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _clearStoredImage() async {
    setState(() {
      _isLoading = true;
      _testResult = "Clearing stored image...";
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('employee_image_${widget.employeeId}');

      setState(() {
        _storedImage = null;
        _imageLength = 0;
        _testResult = "Stored image cleared successfully";
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _testResult = "Error clearing image: $e";
        _isLoading = false;
      });
    }
  }
}