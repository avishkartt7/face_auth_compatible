// lib/services/service_locator.dart (updated)

import 'package:get_it/get_it.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';
import 'package:face_auth_compatible/services/database_helper.dart';
import 'package:face_auth_compatible/services/sync_service.dart';
import 'package:face_auth_compatible/repositories/attendance_repository.dart';
import 'package:face_auth_compatible/repositories/location_repository.dart';
import 'package:face_auth_compatible/services/secure_face_storage_service.dart';
// Add import for our new repository
import 'package:face_auth_compatible/repositories/check_out_request_repository.dart';
// Add import for notification service
import 'package:face_auth_compatible/services/notification_service.dart';
// Add import for FCM token service
import 'package:face_auth_compatible/services/fcm_token_service.dart';

final GetIt getIt = GetIt.instance;

void setupServiceLocator() {
  // Services
  getIt.registerSingleton<DatabaseHelper>(DatabaseHelper());
  getIt.registerSingleton<ConnectivityService>(ConnectivityService());
  getIt.registerSingleton<SecureFaceStorageService>(SecureFaceStorageService());

  // Register notification service
  getIt.registerSingleton<NotificationService>(NotificationService());

  // Register FCM token service
  getIt.registerSingleton<FcmTokenService>(FcmTokenService());

  // Repositories
  getIt.registerSingleton<AttendanceRepository>(
    AttendanceRepository(
      dbHelper: getIt<DatabaseHelper>(),
      connectivityService: getIt<ConnectivityService>(),
    ),
  );

  getIt.registerSingleton<LocationRepository>(
    LocationRepository(
      dbHelper: getIt<DatabaseHelper>(),
      connectivityService: getIt<ConnectivityService>(),
    ),
  );

  // Register check-out request repository
  getIt.registerSingleton<CheckOutRequestRepository>(
    CheckOutRequestRepository(
      dbHelper: getIt<DatabaseHelper>(),
      connectivityService: getIt<ConnectivityService>(),
    ),
  );

  // SyncService needs repos to be registered first
  getIt.registerLazySingleton<SyncService>(
        () => SyncService(
      connectivityService: getIt<ConnectivityService>(),
      attendanceRepository: getIt<AttendanceRepository>(),
      checkOutRequestRepository: getIt.get<CheckOutRequestRepository>(), // Add checkout repository to sync service
    ),
  );
}