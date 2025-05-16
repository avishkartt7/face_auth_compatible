// lib/services/secure_face_storage_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:face_auth_compatible/model/user_model.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class SecureFaceStorageService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Company/App identifier for external storage
  static const String _companyId = 'PhoenicianHR';
  static const String _appDataFolder = 'FaceData';

  // Get truly persistent storage directory
  Future<Directory?> getPersistentStorageDirectory() async {
    if (!Platform.isAndroid) return null;

    try {
      // First try regular storage permissions
      bool hasPermission = await _requestStoragePermission();

      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

      // For Android 11+ (API 30+), or if permissions were denied,
      // use the fallback directory that doesn't require special permissions
      if (androidInfo.version.sdkInt >= 30 || !hasPermission) {
        return await _getFallbackStorageDirectory();
      }

      // For Android 10 and below with granted permissions, use the Documents directory
      if (hasPermission) {
        final Directory? externalDir = await getExternalStorageDirectory();
        if (externalDir == null) {
          print("SecureFaceStorage: External storage not available");
          return await _getFallbackStorageDirectory();
        }

        // Extract the root path (typically /storage/emulated/0)
        String storagePath = externalDir.path.split('Android')[0];

        // Create our persistent directory in Documents
        final Directory persistentDir = Directory('$storagePath/Documents/$_companyId/$_appDataFolder');

        // Create directory if it doesn't exist
        if (!await persistentDir.exists()) {
          await persistentDir.create(recursive: true);
          print("SecureFaceStorage: Created persistent directory at ${persistentDir.path}");
        }

        return persistentDir;
      }

      // Fallback if something went wrong
      return await _getFallbackStorageDirectory();
    } catch (e) {
      print("SecureFaceStorage: Error getting persistent storage directory: $e");
      // Return fallback directory in case of error
      return await _getFallbackStorageDirectory();
    }
  }

  // Fix for the _requestStoragePermission method in SecureFaceStorageService
  Future<bool> _requestStoragePermission() async {
    try {
      if (!Platform.isAndroid) return true;

      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

      print("SecureFaceStorage: Android SDK: ${androidInfo.version.sdkInt}");

      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+ - Request photos/media permission
        var status = await Permission.photos.status;
        if (!status.isGranted) {
          status = await Permission.photos.request();
        }
        return status.isGranted;
      } else if (androidInfo.version.sdkInt >= 30) {
        // Android 11-12 - Need MANAGE_EXTERNAL_STORAGE
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();

          // If still not granted after request
          if (!status.isGranted) {
            // We cannot show UI here, just log the issue
            print("SecureFaceStorage: MANAGE_EXTERNAL_STORAGE permission denied. User may need to grant it manually in settings.");
          }
        }
        return status.isGranted;
      } else {
        // Android 10 and below - Regular storage permission
        var status = await Permission.storage.status;
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
        return status.isGranted;
      }
    } catch (e) {
      print("SecureFaceStorage: Error requesting storage permission: $e");
      return false;
    }
  }

  void showPermissionExplanationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Storage Permission Required"),
        content: const Text(
          "This app needs storage permission to save face data securely. "
              "You'll be directed to app settings. Please grant 'All files access' permission.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<Directory?> _getFallbackStorageDirectory() async {
    try {
      // Get app's external files directory (doesn't require special permissions)
      final List<Directory>? externalDirs = await getExternalStorageDirectories();
      if (externalDirs != null && externalDirs.isNotEmpty) {
        final Directory fallbackDir = Directory('${externalDirs[0].path}/$_appDataFolder');
        if (!await fallbackDir.exists()) {
          await fallbackDir.create(recursive: true);
        }
        print("SecureFaceStorage: Using fallback directory: ${fallbackDir.path}");
        return fallbackDir;
      }
      return null;
    } catch (e) {
      print("Error getting fallback directory: $e");
      return null;
    }
  }

  Future<void> saveFaceImage(String employeeId, String imageBase64) async {
    try {
      print("SecureFaceStorage: Saving face image for employee $employeeId");

      // Clean the image data
      String cleanedImage = imageBase64;
      if (cleanedImage.contains('data:image') && cleanedImage.contains(',')) {
        cleanedImage = cleanedImage.split(',')[1];
      }

      // CRITICAL: Save to persistent external storage first
      Directory? persistentDir = await getPersistentStorageDirectory();
      if (persistentDir != null) {
        final File persistentFile = File('${persistentDir.path}/${employeeId}_face.dat');

        // Encrypt the data for security
        String encryptedData = _simpleEncrypt(cleanedImage, employeeId);
        await persistentFile.writeAsString(encryptedData);

        print("SecureFaceStorage: Face image saved to persistent storage: ${persistentFile.path}");

        // Create a verification file to ensure data was written
        final File verifyFile = File('${persistentDir.path}/${employeeId}_verify.txt');
        await verifyFile.writeAsString(DateTime.now().toIso8601String());

        // Create metadata file
        final File metaFile = File('${persistentDir.path}/${employeeId}_meta.json');
        Map<String, dynamic> metadata = {
          'employeeId': employeeId,
          'savedAt': DateTime.now().toIso8601String(),
          'imageSize': cleanedImage.length,
          'appVersion': '1.0.0',
          'fileType': 'face_image',
        };
        await metaFile.writeAsString(jsonEncode(metadata));

        print("SecureFaceStorage: Metadata saved");
      } else {
        print("SecureFaceStorage: WARNING - Could not access persistent storage!");
      }

      // Also save to app's internal storage for faster access
      await _saveToInternalStorage(employeeId, cleanedImage);

    } catch (e) {
      print("SecureFaceStorage: Error saving face image: $e");
      rethrow;
    }
  }

  // Save to internal storage (gets cleared on "Clear Storage")
  Future<void> _saveToInternalStorage(String employeeId, String imageData) async {
    try {
      // Save to app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final faceDir = Directory('${appDir.path}/face_data');
      if (!await faceDir.exists()) {
        await faceDir.create(recursive: true);
      }

      final File internalFile = File('${faceDir.path}/${employeeId}_face.dat');
      await internalFile.writeAsString(imageData);

      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('employee_image_$employeeId', imageData);

      // Save to Flutter Secure Storage
      await _secureStorage.write(
        key: 'face_image_$employeeId',
        value: imageData,
      );

      print("SecureFaceStorage: Saved to internal storage");

    } catch (e) {
      print("SecureFaceStorage: Error saving to internal storage: $e");
    }
  }

  // Get face image (checks all locations with persistent storage priority)
  Future<String?> getFaceImage(String employeeId) async {
    try {
      print("SecureFaceStorage: Retrieving face image for employee $employeeId");

      // 1. FIRST CHECK PERSISTENT EXTERNAL STORAGE (survives clear storage)
      Directory? persistentDir = await getPersistentStorageDirectory();
      if (persistentDir != null) {
        final File persistentFile = File('${persistentDir.path}/${employeeId}_face.dat');
        if (await persistentFile.exists()) {
          print("SecureFaceStorage: Found in persistent storage: ${persistentFile.path}");

          String encryptedData = await persistentFile.readAsString();
          String decryptedData = _simpleDecrypt(encryptedData, employeeId);

          // Verify the data is valid
          if (decryptedData.isNotEmpty) {
            print("SecureFaceStorage: Successfully decrypted from persistent storage");

            // Cache it internally for faster access next time
            await _saveToInternalStorage(employeeId, decryptedData);

            return decryptedData;
          }
        } else {
          print("SecureFaceStorage: Not found in persistent storage");
        }
      }

      // 2. Check internal storage (faster but gets cleared)
      final appDir = await getApplicationDocumentsDirectory();
      final File internalFile = File('${appDir.path}/face_data/${employeeId}_face.dat');
      if (await internalFile.exists()) {
        print("SecureFaceStorage: Found in internal storage");
        return await internalFile.readAsString();
      }

      // 3. Check SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      String? cachedImage = prefs.getString('employee_image_$employeeId');
      if (cachedImage != null && cachedImage.isNotEmpty) {
        print("SecureFaceStorage: Found in SharedPreferences");
        return cachedImage;
      }

      // 4. Check Flutter Secure Storage
      String? secureImage = await _secureStorage.read(key: 'face_image_$employeeId');
      if (secureImage != null && secureImage.isNotEmpty) {
        print("SecureFaceStorage: Found in secure storage");
        return secureImage;
      }

      print("SecureFaceStorage: No face image found for employee $employeeId");
      return null;

    } catch (e) {
      print("SecureFaceStorage: Error retrieving face image: $e");
      return null;
    }
  }

  // Save face features to persistent storage
  Future<void> saveFaceFeatures(String employeeId, FaceFeatures features) async {
    try {
      print("SecureFaceStorage: Saving face features for employee $employeeId");

      final String featuresJson = jsonEncode(features.toJson());

      // Save to persistent storage
      Directory? persistentDir = await getPersistentStorageDirectory();
      if (persistentDir != null) {
        final File featuresFile = File('${persistentDir.path}/${employeeId}_features.dat');
        String encryptedData = _simpleEncrypt(featuresJson, employeeId);
        await featuresFile.writeAsString(encryptedData);
        print("SecureFaceStorage: Face features saved to persistent storage");
      }

      // Save to internal storage
      await _saveFeaturesToInternalStorage(employeeId, featuresJson);

    } catch (e) {
      print("SecureFaceStorage: Error saving face features: $e");
      rethrow;
    }
  }

  Future<void> _saveFeaturesToInternalStorage(String employeeId, String featuresJson) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final faceDir = Directory('${appDir.path}/face_data');
      if (!await faceDir.exists()) {
        await faceDir.create(recursive: true);
      }

      final File internalFile = File('${faceDir.path}/${employeeId}_features.dat');
      await internalFile.writeAsString(featuresJson);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('employee_face_features_$employeeId', featuresJson);

    } catch (e) {
      print("SecureFaceStorage: Error saving features to internal storage: $e");
    }
  }

  // Get face features (checks all locations with persistent storage priority)
  Future<FaceFeatures?> getFaceFeatures(String employeeId) async {
    try {
      String? featuresJson;

      // Check persistent storage first
      Directory? persistentDir = await getPersistentStorageDirectory();
      if (persistentDir != null) {
        final File featuresFile = File('${persistentDir.path}/${employeeId}_features.dat');
        if (await featuresFile.exists()) {
          print("SecureFaceStorage: Found features in persistent storage");
          String encryptedData = await featuresFile.readAsString();
          featuresJson = _simpleDecrypt(encryptedData, employeeId);
        }
      }

      // Check internal storage
      if (featuresJson == null) {
        final appDir = await getApplicationDocumentsDirectory();
        final File internalFile = File('${appDir.path}/face_data/${employeeId}_features.dat');
        if (await internalFile.exists()) {
          featuresJson = await internalFile.readAsString();
        }
      }

      // Check SharedPreferences
      if (featuresJson == null) {
        final prefs = await SharedPreferences.getInstance();
        featuresJson = prefs.getString('employee_face_features_$employeeId');
      }

      if (featuresJson != null && featuresJson.isNotEmpty) {
        Map<String, dynamic> jsonMap = jsonDecode(featuresJson);
        return FaceFeatures.fromJson(jsonMap);
      }

      return null;

    } catch (e) {
      print("SecureFaceStorage: Error retrieving face features: $e");
      return null;
    }
  }

  // Set registration status
  Future<void> setFaceRegistered(String employeeId, bool isRegistered) async {
    try {
      // Save to persistent storage
      Directory? persistentDir = await getPersistentStorageDirectory();
      if (persistentDir != null) {
        final File statusFile = File('${persistentDir.path}/${employeeId}_status.txt');
        await statusFile.writeAsString(isRegistered.toString());
        print("SecureFaceStorage: Registration status saved to persistent storage");
      }

      // Save to internal locations
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('face_registered_$employeeId', isRegistered);

      await _secureStorage.write(
        key: 'face_registered_$employeeId',
        value: isRegistered.toString(),
      );

    } catch (e) {
      print("SecureFaceStorage: Error saving registration status: $e");
    }
  }

  // Encryption methods
  String _simpleEncrypt(String text, String key) {
    final keyBytes = utf8.encode(key.padRight(32).substring(0, 32));
    final textBytes = utf8.encode(text);
    final encrypted = List<int>.generate(textBytes.length, (i) {
      return textBytes[i] ^ keyBytes[i % keyBytes.length];
    });
    return base64Encode(encrypted);
  }

  String _simpleDecrypt(String encrypted, String key) {
    final keyBytes = utf8.encode(key.padRight(32).substring(0, 32));
    final encryptedBytes = base64Decode(encrypted);
    final decrypted = List<int>.generate(encryptedBytes.length, (i) {
      return encryptedBytes[i] ^ keyBytes[i % keyBytes.length];
    });
    return utf8.decode(decrypted);
  }

  // Check if face is registered
  Future<bool> isFaceRegistered(String employeeId) async {
    // Check if we have face image in any location
    String? faceImage = await getFaceImage(employeeId);
    return faceImage != null && faceImage.isNotEmpty;
  }

  // Delete all face data (for cleanup)
  Future<void> deleteFaceData(String employeeId) async {
    try {
      // Delete from persistent storage
      Directory? persistentDir = await getPersistentStorageDirectory();
      if (persistentDir != null) {
        final files = [
          File('${persistentDir.path}/${employeeId}_face.dat'),
          File('${persistentDir.path}/${employeeId}_features.dat'),
          File('${persistentDir.path}/${employeeId}_status.txt'),
          File('${persistentDir.path}/${employeeId}_meta.json'),
          File('${persistentDir.path}/${employeeId}_verify.txt'),
        ];

        for (var file in files) {
          if (await file.exists()) {
            await file.delete();
          }
        }
      }

      // Delete from internal storage
      final appDir = await getApplicationDocumentsDirectory();
      final internalFiles = [
        File('${appDir.path}/face_data/${employeeId}_face.dat'),
        File('${appDir.path}/face_data/${employeeId}_features.dat'),
      ];

      for (var file in internalFiles) {
        if (await file.exists()) {
          await file.delete();
        }
      }

      // Delete from SharedPreferences and Secure Storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('employee_image_$employeeId');
      await prefs.remove('employee_face_features_$employeeId');
      await prefs.remove('face_registered_$employeeId');

      await _secureStorage.delete(key: 'face_image_$employeeId');
      await _secureStorage.delete(key: 'face_registered_$employeeId');

    } catch (e) {
      print("SecureFaceStorage: Error deleting face data: $e");
    }
  }
}