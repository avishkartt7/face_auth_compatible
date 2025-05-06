// lib/settings/settings_view.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:flutter_face_api/face_api.dart' as regula;

class SettingsView extends StatefulWidget {
  final String employeeId;

  const SettingsView({
    Key? key,
    required this.employeeId,
  }) : super(key: key);

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _isDarkMode = false;
  bool _offlineMode = false;
  bool _isTesting = false;
  bool _hasStoredImage = false;
  int _imageSize = 0;
  String _imageFormat = "Unknown";
  String _testResult = "";

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkStoredImage();
  }

  Future<void> _loadSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _saveDarkModeSetting(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
    setState(() {
      _isDarkMode = value;
    });
  }

  Future<void> _checkStoredImage() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? storedImage = prefs.getString('employee_image_${widget.employeeId}');

      setState(() {
        _hasStoredImage = storedImage != null && storedImage.isNotEmpty;
        _imageSize = storedImage?.length ?? 0;

        // Try to determine format
        if (storedImage != null && storedImage.isNotEmpty) {
          if (storedImage.startsWith('data:image/jpeg')) {
            _imageFormat = "JPEG (data URL)";
          } else if (storedImage.startsWith('data:image/png')) {
            _imageFormat = "PNG (data URL)";
          } else if (storedImage.startsWith('/9j/')) {
            _imageFormat = "JPEG (base64)";
          } else if (storedImage.startsWith('iVBOR')) {
            _imageFormat = "PNG (base64)";
          } else {
            _imageFormat = "Unknown format";
          }
        }
      });
    } catch (e) {
      debugPrint("Error checking stored image: $e");
    }
  }

  Future<void> _simulateOfflineMode(bool value) async {
    setState(() {
      _offlineMode = value;
    });

    // Get the connectivity service from the service locator and set offline mode
    final connectivityService = getIt<ConnectivityService>();
    connectivityService.setOfflineModeForTesting(value);

    CustomSnackBar.successSnackBar(
        value ? "Offline mode simulated" : "Online mode restored"
    );
  }

  Future<void> _testImageRetrieval() async {
    setState(() {
      _isTesting = true;
      _testResult = "Testing...";
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? imageData = prefs.getString('employee_image_${widget.employeeId}');

      if (imageData == null || imageData.isEmpty) {
        setState(() {
          _testResult = "❌ No stored image found";
          _isTesting = false;
        });
        return;
      }

      // Clean the format if needed
      String cleanImage = imageData;
      if (imageData.contains('data:image') && imageData.contains(',')) {
        cleanImage = imageData.split(',')[1];
      }

      // Try base64 decoding
      try {
        Uint8List bytes = base64Decode(cleanImage);
        setState(() {
          _testResult = "✓ Successfully decoded ${bytes.length} bytes";
        });
      } catch (e) {
        setState(() {
          _testResult = "❌ Failed to decode image: $e";
        });
        return;
      }

      // Try using the Regula SDK
      try {
        var image = regula.MatchFacesImage();
        image.bitmap = cleanImage;
        image.imageType = regula.ImageType.PRINTED;

        // Verify with the SDK that the image is valid
        dynamic value = await regula.FaceSDK.detectFaces(jsonEncode({"image": image}));
        var result = json.decode(value);

        if (result != null && result['faces'] != null && result['faces'].length > 0) {
          setState(() {
            _testResult += "\n✓ Regula SDK successfully detected ${result['faces'].length} face(s)";
          });
        } else {
          setState(() {
            _testResult += "\n❌ Regula SDK couldn't detect any faces";
          });
        }
      } catch (e) {
        setState(() {
          _testResult += "\n❌ SDK error: $e";
        });
      }
    } catch (e) {
      setState(() {
        _testResult = "❌ Error in test: $e";
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  Future<void> _simulateOfflineMode(bool value) async {
    setState(() {
      _offlineMode = value;
    });

    // Here you would implement actual offline mode simulation
    // This is just a placeholder for your implementation
    CustomSnackBar.successSnackBar(
        value ? "Offline mode simulated" : "Online mode restored"
    );
  }

  Future<void> _clearStoredImage() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('employee_image_${widget.employeeId}');

      CustomSnackBar.successSnackBar("Stored image cleared");
      _checkStoredImage();
    } catch (e) {
      CustomSnackBar.errorSnackBar("Error clearing image: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings & Diagnostics"),
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // App Settings Section
              _buildSectionHeader("App Settings"),
              _buildSettingTile(
                title: "Dark Mode",
                subtitle: "Switch between light and dark theme",
                icon: Icons.dark_mode,
                trailing: Switch(
                  value: _isDarkMode,
                  onChanged: _saveDarkModeSetting,
                  activeColor: accentColor,
                ),
              ),

              const SizedBox(height: 20),

              // Offline Testing Section
              _buildSectionHeader("Offline Authentication Testing"),
              _buildSettingTile(
                title: "Simulate Offline Mode",
                subtitle: "Test app functionality without network",
                icon: Icons.wifi_off,
                trailing: Switch(
                  value: _offlineMode,
                  onChanged: _simulateOfflineMode,
                  activeColor: accentColor,
                ),
              ),

              // Facial authentication testing
              const SizedBox(height: 10),
              _buildFaceAuthCard(),

              const SizedBox(height: 20),

              // Debug Info Section
              _buildSectionHeader("Debug Information"),
              _buildInfoTile(
                title: "Employee ID",
                value: widget.employeeId,
              ),
              _buildInfoTile(
                title: "App Version",
                value: "1.0.0",
              ),

              // More settings (for future expansion)
              const SizedBox(height: 20),
              _buildSectionHeader("More Settings"),
              _buildSettingTile(
                title: "Privacy Settings",
                subtitle: "Manage your data and privacy preferences",
                icon: Icons.privacy_tip,
                onTap: () => CustomSnackBar.successSnackBar("Feature coming soon"),
              ),
              _buildSettingTile(
                title: "Notifications",
                subtitle: "Configure app notifications",
                icon: Icons.notifications,
                onTap: () => CustomSnackBar.successSnackBar("Feature coming soon"),
              ),
              _buildSettingTile(
                title: "About",
                subtitle: "Learn more about this app",
                icon: Icons.info,
                onTap: () => CustomSnackBar.successSnackBar("Feature coming soon"),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: accentColor.withOpacity(0.2),
          child: Icon(icon, color: accentColor),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }

  Widget _buildInfoTile({
    required String title,
    required String value,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaceAuthCard() {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Face Authentication Storage",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),

            // Storage info
            _buildStorageInfoRow(
              title: "Stored Face Image",
              value: _hasStoredImage ? "✓ Available" : "❌ Not found",
              valueColor: _hasStoredImage ? Colors.green : Colors.red,
            ),
            _buildStorageInfoRow(
              title: "Image Size",
              value: _hasStoredImage ? "$_imageSize bytes" : "N/A",
            ),
            _buildStorageInfoRow(
              title: "Format",
              value: _hasStoredImage ? _imageFormat : "N/A",
            ),

            const SizedBox(height: 16),

            // Test result
            if (_testResult.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  _testResult,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: _testResult.contains("❌") ? Colors.red : Colors.green.shade800,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: _isTesting ? null : _testImageRetrieval,
                  icon: _isTesting
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)
                  )
                      : const Icon(Icons.check),
                  label: const Text("Test Retrieval"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _hasStoredImage ? _clearStoredImage : null,
                  icon: const Icon(Icons.delete),
                  label: const Text("Clear Image"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageInfoRow({
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade700,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}