// lib/services/face_data_migration_service.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:face_auth_compatible/services/secure_face_storage_service.dart';
import 'package:face_auth_compatible/model/user_model.dart';

class FaceDataMigrationService {
  final SecureFaceStorageService _storageService;

  FaceDataMigrationService(this._storageService);

  Future<void> migrateExistingData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // Find all employee image keys
      for (String key in keys) {
        if (key.startsWith('employee_image_')) {
          String employeeId = key.replaceFirst('employee_image_', '');
          String? imageData = prefs.getString(key);

          if (imageData != null && imageData.isNotEmpty) {
            // Save to external storage
            await _storageService.saveFaceImage(employeeId, imageData);
            print("Migrated face image for employee: $employeeId");
          }
        }

        if (key.startsWith('employee_face_features_')) {
          String employeeId = key.replaceFirst('employee_face_features_', '');
          String? featuresJson = prefs.getString(key);

          if (featuresJson != null && featuresJson.isNotEmpty) {
            Map<String, dynamic> jsonMap = jsonDecode(featuresJson);
            FaceFeatures features = FaceFeatures.fromJson(jsonMap);
            await _storageService.saveFaceFeatures(employeeId, features);
            print("Migrated face features for employee: $employeeId");
          }
        }
      }
    } catch (e) {
      print("Error migrating face data: $e");
    }
  }
}