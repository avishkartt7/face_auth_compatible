// lib/services/secure_face_storage_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:face_auth_compatible/model/user_model.dart';

class SecureFaceStorageService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Key prefixes
  static const String _faceImagePrefix = 'secure_face_image_';
  static const String _faceFeaturesPrefix = 'secure_face_features_';
  static const String _faceRegistrationPrefix = 'secure_face_registered_';

  // Get the app's data directory - this directory persists even if cache is cleared
  Future<String> getAppDataDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    // Create a specific directory for face data
    final faceDataDir = Directory('${appDir.path}/face_data');
    if (!await faceDataDir.exists()) {
      await faceDataDir.create(recursive: true);
    }
    return faceDataDir.path;
  }

  // Save face image to file instead of just secure storage for extra persistence
  Future<void> saveFaceImageToFile(String employeeId, String imageBase64) async {
    try {
      String dataDir = await getAppDataDirectory();
      File imageFile = File('$dataDir/${employeeId}_face.dat');

      // Encrypt or encode the image data for extra security if needed
      await imageFile.writeAsString(imageBase64);

      // Store the file path in secure storage
      await _secureStorage.write(
        key: '${_faceImagePrefix}file_${employeeId}',
        value: imageFile.path,
      );

      print("Face image saved to persistent file: ${imageFile.path}");
    } catch (e) {
      print("Error saving face image to file: $e");
      // Fall back to regular secure storage
    }
  }

  // Get face image from file if available
  Future<String?> getFaceImageFromFile(String employeeId) async {
    try {
      // Get file path from secure storage
      String? filePath = await _secureStorage.read(
        key: '${_faceImagePrefix}file_${employeeId}',
      );

      if (filePath != null) {
        File imageFile = File(filePath);
        if (await imageFile.exists()) {
          return await imageFile.readAsString();
        }
      }
      return null;
    } catch (e) {
      print("Error reading face image from file: $e");
      return null;
    }
  }

  // Save face image
  Future<void> saveFaceImage(String employeeId, String imageBase64) async {
    // Clean the image data before storing
    String cleanedImage = imageBase64;
    if (cleanedImage.contains('data:image') && cleanedImage.contains(',')) {
      cleanedImage = cleanedImage.split(',')[1];
    }

    // First save to secure storage
    await _secureStorage.write(
      key: _faceImagePrefix + employeeId,
      value: cleanedImage,
    );

    // Also save to file for extra persistence
    await saveFaceImageToFile(employeeId, cleanedImage);

    // Also mirror to SharedPreferences for backward compatibility
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('employee_image_$employeeId', cleanedImage);
  }

  // Get face image
  Future<String?> getFaceImage(String employeeId) async {
    try {
      // First try to get from secure storage
      String? image = await _secureStorage.read(key: _faceImagePrefix + employeeId);

      // If not found, try from file storage
      if (image == null) {
        image = await getFaceImageFromFile(employeeId);
      }

      // If still not found, try SharedPreferences as fallback
      if (image == null) {
        final prefs = await SharedPreferences.getInstance();
        image = prefs.getString('employee_image_$employeeId');

        // If found in SharedPreferences, migrate it to secure storage and file
        if (image != null) {
          await saveFaceImage(employeeId, image);
        }
      }

      return image;
    } catch (e) {
      print("Error retrieving face image: $e");
      return null;
    }
  }

  // Save face features to file
  Future<void> saveFeaturesToFile(String employeeId, FaceFeatures features) async {
    try {
      String dataDir = await getAppDataDirectory();
      File featuresFile = File('$dataDir/${employeeId}_features.dat');

      String featuresJson = jsonEncode(features.toJson());
      await featuresFile.writeAsString(featuresJson);

      // Store the file path in secure storage
      await _secureStorage.write(
        key: '${_faceFeaturesPrefix}file_${employeeId}',
        value: featuresFile.path,
      );

      print("Face features saved to persistent file: ${featuresFile.path}");
    } catch (e) {
      print("Error saving face features to file: $e");
    }
  }

  // Get face features from file
  Future<FaceFeatures?> getFeaturesFromFile(String employeeId) async {
    try {
      // Get file path from secure storage
      String? filePath = await _secureStorage.read(
        key: '${_faceFeaturesPrefix}file_${employeeId}',
      );

      if (filePath != null) {
        File featuresFile = File(filePath);
        if (await featuresFile.exists()) {
          String featuresJson = await featuresFile.readAsString();
          Map<String, dynamic> jsonMap = jsonDecode(featuresJson);
          return FaceFeatures.fromJson(jsonMap);
        }
      }
      return null;
    } catch (e) {
      print("Error reading face features from file: $e");
      return null;
    }
  }

  // Save face features
  Future<void> saveFaceFeatures(String employeeId, FaceFeatures features) async {
    final String featuresJson = jsonEncode(features.toJson());

    // First save to secure storage
    await _secureStorage.write(
      key: _faceFeaturesPrefix + employeeId,
      value: featuresJson,
    );

    // Also save to file for extra persistence
    await saveFeaturesToFile(employeeId, features);

    // Mirror to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('employee_face_features_$employeeId', featuresJson);
  }

  // Get face features
  Future<FaceFeatures?> getFaceFeatures(String employeeId) async {
    try {
      // First check secure storage
      String? featuresJson = await _secureStorage.read(key: _faceFeaturesPrefix + employeeId);

      // If not found, try from file
      if (featuresJson == null) {
        FaceFeatures? features = await getFeaturesFromFile(employeeId);
        if (features != null) {
          return features;
        }
      }

      // Fallback to SharedPreferences
      if (featuresJson == null) {
        final prefs = await SharedPreferences.getInstance();
        featuresJson = prefs.getString('employee_face_features_$employeeId');

        // Migrate if found
        if (featuresJson != null) {
          Map<String, dynamic> jsonMap = jsonDecode(featuresJson);
          FaceFeatures features = FaceFeatures.fromJson(jsonMap);

          // Save to secure storage and file for next time
          await saveFaceFeatures(employeeId, features);
        }
      }

      if (featuresJson != null) {
        Map<String, dynamic> jsonMap = jsonDecode(featuresJson);
        return FaceFeatures.fromJson(jsonMap);
      }

      return null;
    } catch (e) {
      print("Error retrieving face features: $e");
      return null;
    }
  }

  // Set registration status
  Future<void> setFaceRegistered(String employeeId, bool isRegistered) async {
    await _secureStorage.write(
      key: _faceRegistrationPrefix + employeeId,
      value: isRegistered.toString(),
    );

    // Also save to file
    try {
      String dataDir = await getAppDataDirectory();
      File statusFile = File('$dataDir/${employeeId}_status.dat');
      await statusFile.writeAsString(isRegistered.toString());
    } catch (e) {
      print("Error saving status to file: $e");
    }

    // Mirror to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('face_registered_$employeeId', isRegistered);
  }

  // Check if face is registered
  Future<bool> isFaceRegistered(String employeeId) async {
    try {
      // First check secure storage
      String? status = await _secureStorage.read(key: _faceRegistrationPrefix + employeeId);

      // If not found, check file
      if (status == null) {
        try {
          String dataDir = await getAppDataDirectory();
          File statusFile = File('$dataDir/${employeeId}_status.dat');
          if (await statusFile.exists()) {
            status = await statusFile.readAsString();
          }
        } catch (e) {
          print("Error reading status from file: $e");
        }
      }

      // If still not found, check SharedPreferences
      if (status == null) {
        // Check SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        bool? registeredStatus = prefs.getBool('face_registered_$employeeId');

        if (registeredStatus != null) {
          // Migrate to secure storage
          await setFaceRegistered(employeeId, registeredStatus);
          return registeredStatus;
        }

        return false;
      }

      return status.toLowerCase() == 'true';
    } catch (e) {
      print("Error checking face registration: $e");
      return false;
    }
  }

  // Delete all face data for a user
  Future<void> deleteFaceData(String employeeId) async {
    try {
      // Delete from secure storage
      await _secureStorage.delete(key: _faceImagePrefix + employeeId);
      await _secureStorage.delete(key: _faceFeaturesPrefix + employeeId);
      await _secureStorage.delete(key: _faceRegistrationPrefix + employeeId);
      await _secureStorage.delete(key: '${_faceImagePrefix}file_${employeeId}');
      await _secureStorage.delete(key: '${_faceFeaturesPrefix}file_${employeeId}');

      // Delete files
      String dataDir = await getAppDataDirectory();
      File imageFile = File('$dataDir/${employeeId}_face.dat');
      File featuresFile = File('$dataDir/${employeeId}_features.dat');
      File statusFile = File('$dataDir/${employeeId}_status.dat');

      if (await imageFile.exists()) await imageFile.delete();
      if (await featuresFile.exists()) await featuresFile.delete();
      if (await statusFile.exists()) await statusFile.delete();

      // Clean up SharedPreferences too
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('employee_image_$employeeId');
      await prefs.remove('employee_face_features_$employeeId');
      await prefs.remove('face_registered_$employeeId');
    } catch (e) {
      print("Error deleting face data: $e");
    }
  }
}