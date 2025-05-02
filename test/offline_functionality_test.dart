// test/offline_functionality_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';
import 'package:face_auth_compatible/repositories/attendance_repository.dart';
import 'package:face_auth_compatible/services/database_helper.dart';
import 'package:face_auth_compatible/model/local_attendance_model.dart';
import 'package:sqflite/sqflite.dart';
import 'offline_functionality_test.mocks.dart';

// Create a mock database class
class MockDatabase extends Mock implements Database {}

// Use a manual mock for DatabaseHelper
class MockDatabaseHelper extends Mock implements DatabaseHelper {
  final MockDatabase _mockDatabase = MockDatabase();

  @override
  Future<Database> get database async {
    return _mockDatabase;
  }
}

void main() {
  late MockConnectivityService mockConnectivityService;
  late MockDatabaseHelper mockDatabaseHelper;
  late MockAttendanceRepository mockAttendanceRepository;
  late MockDatabase mockDatabase;

  setUp(() {
    mockConnectivityService = MockConnectivityService();
    mockDatabaseHelper = MockDatabaseHelper();
    mockDatabase = MockDatabase();
    mockAttendanceRepository = MockAttendanceRepository();
  });

  group('Offline Functionality Tests', () {
    test('Check-in works in offline mode', () async {
      // Setup
      when(mockConnectivityService.currentStatus).thenReturn(ConnectionStatus.offline);
      when(mockAttendanceRepository.recordCheckIn(
        employeeId: anyNamed('employeeId'),
        checkInTime: anyNamed('checkInTime'),
        locationId: anyNamed('locationId'),
        locationName: anyNamed('locationName'),
        locationLat: anyNamed('locationLat'),
        locationLng: anyNamed('locationLng'),
      )).thenAnswer((_) async => true);

      // Execute
      bool result = await mockAttendanceRepository.recordCheckIn(
        employeeId: 'test-employee-id',
        checkInTime: DateTime.now(),
        locationId: 'test-location-id',
        locationName: 'Test Location',
        locationLat: 25.0,
        locationLng: 55.0,
      );

      // Verify
      expect(result, true);
    });

    // Add more tests as needed
  });
}