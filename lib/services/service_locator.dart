import 'package:get_it/get_it.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/repositories/location_repository.dart';
import 'package:face_auth_compatible/repositories/attendance_repository.dart';
import 'package:face_auth_compatible/repositories/check_out_request_repository.dart';
import 'package:face_auth_compatible/services/database_helper.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';
import 'package:face_auth_compatible/services/notification_service.dart';
import 'package:face_auth_compatible/services/fcm_token_service.dart';
import 'package:face_auth_compatible/services/sync_service.dart';
import 'package:face_auth_compatible/services/secure_face_storage_service.dart';

final GetIt getIt = GetIt.instance;

void setupServiceLocator() {
  // Register database helper
  getIt.registerLazySingleton<DatabaseHelper>(() => DatabaseHelper());

  // Register connectivity service
  getIt.registerLazySingleton<ConnectivityService>(() => ConnectivityService());

  // Register secure storage service
  getIt.registerLazySingleton<SecureFaceStorageService>(() => SecureFaceStorageService());

  // Register repositories
  getIt.registerLazySingleton<LocationRepository>(
        () => LocationRepository(
      firestore: FirebaseFirestore.instance,
      dbHelper: getIt<DatabaseHelper>(),
      connectivityService: getIt<ConnectivityService>(),
    ),
  );

  getIt.registerLazySingleton<AttendanceRepository>(
        () => AttendanceRepository(
      firestore: FirebaseFirestore.instance,
      dbHelper: getIt<DatabaseHelper>(),
      connectivityService: getIt<ConnectivityService>(),
    ),
  );

  getIt.registerLazySingleton<CheckOutRequestRepository>(
        () => CheckOutRequestRepository(
      firestore: FirebaseFirestore.instance,
      dbHelper: getIt<DatabaseHelper>(),
      connectivityService: getIt<ConnectivityService>(),
    ),
  );

  // Register notification services
  getIt.registerLazySingleton<NotificationService>(() => NotificationService());

  // Register FCM token service
  getIt.registerLazySingleton<FcmTokenService>(() => FcmTokenService());

  // Register sync service (depends on repositories)
  getIt.registerLazySingleton<SyncService>(
        () => SyncService(
      attendanceRepository: getIt<AttendanceRepository>(),
      checkOutRequestRepository: getIt<CheckOutRequestRepository>(),
      connectivityService: getIt<ConnectivityService>(),
    ),
  );
}