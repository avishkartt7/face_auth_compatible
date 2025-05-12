// lib/services/service_locator.dart

import 'package:get_it/get_it.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';
import 'package:face_auth_compatible/services/database_helper.dart';
import 'package:face_auth_compatible/services/sync_service.dart';
import 'package:face_auth_compatible/repositories/attendance_repository.dart';
import 'package:face_auth_compatible/repositories/location_repository.dart';

final GetIt getIt = GetIt.instance;

void setupServiceLocator() {
  // Services
  getIt.registerSingleton<DatabaseHelper>(DatabaseHelper());
  getIt.registerSingleton<ConnectivityService>(ConnectivityService());

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

  // SyncService needs repos to be registered first
  // Use lazy singleton to ensure it's created after all dependencies
  getIt.registerLazySingleton<SyncService>(
        () => SyncService(
      connectivityService: getIt<ConnectivityService>(),
      attendanceRepository: getIt<AttendanceRepository>(),
    ),
  );
}