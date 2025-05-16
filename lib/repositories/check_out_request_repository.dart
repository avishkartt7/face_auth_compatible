// lib/repositories/check_out_request_repository.dart - Updated version

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/model/check_out_request_model.dart';
import 'package:face_auth_compatible/services/database_helper.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CheckOutRequestRepository {
  final DatabaseHelper _dbHelper;
  final FirebaseFirestore _firestore;
  final ConnectivityService _connectivityService;

  CheckOutRequestRepository({
    required DatabaseHelper dbHelper,
    FirebaseFirestore? firestore,
    required ConnectivityService connectivityService,
  }) : _dbHelper = dbHelper,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _connectivityService = connectivityService;

  // Create the check-out request table in the local database if needed
  Future<void> _ensureTableExists() async {
    final db = await _dbHelper.database;

    // Check if table exists
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='check_out_requests'"
    );

    if (tables.isEmpty) {
      // Create the table with requestType column
      await db.execute('''
      CREATE TABLE check_out_requests(
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        employee_name TEXT NOT NULL,
        line_manager_id TEXT NOT NULL,
        request_time TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        location_name TEXT NOT NULL,
        reason TEXT NOT NULL,
        status TEXT NOT NULL,
        response_time TEXT,
        response_message TEXT,
        is_synced INTEGER DEFAULT 0,
        local_id TEXT,
        request_type TEXT DEFAULT 'check-out'
      )
    ''');
      print("Created check_out_requests table");
    } else {
      // Check if requestType column exists, add it if it doesn't
      try {
        await db.rawQuery("SELECT request_type FROM check_out_requests LIMIT 1");
      } catch (e) {
        // Column doesn't exist, add it
        await db.execute(
            "ALTER TABLE check_out_requests ADD COLUMN request_type TEXT DEFAULT 'check-out'");
        print("Added request_type column to existing table");
      }
    }
  }

  // Create a new check-out request
  Future<bool> createCheckOutRequest(CheckOutRequest request) async {
    try {
      // Ensure the table exists
      await _ensureTableExists();

      // Generate a local ID if we're offline
      String localId = DateTime.now().millisecondsSinceEpoch.toString();
      String? remoteId;

      // If online, try to save to Firestore first
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        try {
          final docRef = await _firestore.collection('check_out_requests').add(request.toMap());
          remoteId = docRef.id;
          print("Saved request to Firestore with ID: $remoteId");
        } catch (e) {
          print("Error saving request to Firestore: $e");
          // Continue with local storage even if Firestore fails
        }
      }

      // Always save to local storage
      Map<String, dynamic> localData = {
        'id': remoteId ?? localId, // Use Firestore ID if available
        'employee_id': request.employeeId,
        'employee_name': request.employeeName,
        'line_manager_id': request.lineManagerId,
        'request_time': request.requestTime.toIso8601String(),
        'latitude': request.latitude,
        'longitude': request.longitude,
        'location_name': request.locationName,
        'reason': request.reason,
        'status': request.status.toString().split('.').last,
        'response_time': request.responseTime?.toIso8601String(),
        'response_message': request.responseMessage,
        'is_synced': remoteId != null ? 1 : 0,
        'local_id': localId,
        'request_type': request.requestType,
      };

      await _dbHelper.insert('check_out_requests', localData);
      print("Saved request locally with ID: ${remoteId ?? localId}");

      return true;
    } catch (e) {
      print("Error creating request: $e");
      return false;
    }
  }

  // Get all pending requests for a specific line manager
  Future<List<CheckOutRequest>> getPendingRequestsForManager(String lineManagerId) async {
    try {
      await _ensureTableExists();
      List<CheckOutRequest> requests = [];

      // Check online first if possible
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        try {
          final snapshot = await _firestore
              .collection('check_out_requests')
              .where('lineManagerId', isEqualTo: lineManagerId)
              .where('status', isEqualTo: CheckOutRequestStatus.pending.toString().split('.').last)
              .orderBy('requestTime', descending: true)
              .get();

          requests = snapshot.docs.map((doc) {
            return CheckOutRequest.fromMap(doc.data(), doc.id);
          }).toList();

          // Also cache these requests locally
          for (var request in requests) {
            await _saveRequestLocally(request);
          }

          return requests;
        } catch (e) {
          print("Error fetching requests from Firestore: $e");
          // Fall back to local data
        }
      }

      // Get from local storage
      final localRequests = await _dbHelper.query(
        'check_out_requests',
        where: 'line_manager_id = ? AND status = ?',
        whereArgs: [lineManagerId, CheckOutRequestStatus.pending.toString().split('.').last],
        orderBy: 'request_time DESC',
      );

      return localRequests.map((map) {
        // Convert from SQLite format to our model
        final formattedMap = {
          'employeeId': map['employee_id'],
          'employeeName': map['employee_name'],
          'lineManagerId': map['line_manager_id'],
          'requestTime': Timestamp.fromDate(DateTime.parse(map['request_time'] as String)),
          'latitude': map['latitude'],
          'longitude': map['longitude'],
          'locationName': map['location_name'],
          'reason': map['reason'],
          'status': map['status'],
          'responseTime': map['response_time'] != null
              ? Timestamp.fromDate(DateTime.parse(map['response_time'] as String))
              : null,
          'responseMessage': map['response_message'],
          'requestType': map['request_type'] ?? 'check-out', // Default for backward compatibility
        };

        return CheckOutRequest.fromMap(formattedMap, map['id'] as String);
      }).toList();
    } catch (e) {
      print("Error getting pending requests: $e");
      return [];
    }
  }

  // Get all requests for a specific employee
  Future<List<CheckOutRequest>> getRequestsForEmployee(String employeeId) async {
    try {
      await _ensureTableExists();
      List<CheckOutRequest> requests = [];

      // Check online first if possible
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        try {
          final snapshot = await _firestore
              .collection('check_out_requests')
              .where('employeeId', isEqualTo: employeeId)
              .orderBy('requestTime', descending: true)
              .get();

          requests = snapshot.docs.map((doc) {
            return CheckOutRequest.fromMap(doc.data(), doc.id);
          }).toList();

          // Also cache these requests locally
          for (var request in requests) {
            await _saveRequestLocally(request);
          }

          return requests;
        } catch (e) {
          print("Error fetching requests from Firestore: $e");
          // Fall back to local data
        }
      }

      // Get from local storage
      final localRequests = await _dbHelper.query(
        'check_out_requests',
        where: 'employee_id = ?',
        whereArgs: [employeeId],
        orderBy: 'request_time DESC',
      );

      return localRequests.map((map) {
        // Convert from SQLite format to our model
        final formattedMap = {
          'employeeId': map['employee_id'],
          'employeeName': map['employee_name'],
          'lineManagerId': map['line_manager_id'],
          'requestTime': Timestamp.fromDate(DateTime.parse(map['request_time'] as String)),
          'latitude': map['latitude'],
          'longitude': map['longitude'],
          'locationName': map['location_name'],
          'reason': map['reason'],
          'status': map['status'],
          'responseTime': map['response_time'] != null
              ? Timestamp.fromDate(DateTime.parse(map['response_time'] as String))
              : null,
          'responseMessage': map['response_message'],
          'requestType': map['request_type'] ?? 'check-out', // Default for backward compatibility
        };

        return CheckOutRequest.fromMap(formattedMap, map['id'] as String);
      }).toList();
    } catch (e) {
      print("Error getting employee requests: $e");
      return [];
    }
  }

  // Respond to a request (approve or reject)
  Future<bool> respondToRequest(String requestId, CheckOutRequestStatus newStatus, String? message) async {
    try {
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        // Update in Firestore
        await _firestore.collection('check_out_requests').doc(requestId).update({
          'status': newStatus.toString().split('.').last,
          'responseTime': FieldValue.serverTimestamp(),
          'responseMessage': message,
        });

        // Update local copy
        await _dbHelper.update(
          'check_out_requests',
          {
            'status': newStatus.toString().split('.').last,
            'response_time': DateTime.now().toIso8601String(),
            'response_message': message,
            'is_synced': 1,
          },
          where: 'id = ?',
          whereArgs: [requestId],
        );

        return true;
      } else {
        // Offline mode - just update locally and mark for sync
        await _dbHelper.update(
          'check_out_requests',
          {
            'status': newStatus.toString().split('.').last,
            'response_time': DateTime.now().toIso8601String(),
            'response_message': message,
            'is_synced': 0,
          },
          where: 'id = ?',
          whereArgs: [requestId],
        );

        return true;
      }
    } catch (e) {
      print("Error responding to request: $e");
      return false;
    }
  }

  // Save a request to local storage
  Future<void> _saveRequestLocally(CheckOutRequest request) async {
    try {
      // Check if it already exists
      final existingRequests = await _dbHelper.query(
        'check_out_requests',
        where: 'id = ?',
        whereArgs: [request.id],
      );

      Map<String, dynamic> localData = {
        'id': request.id,
        'employee_id': request.employeeId,
        'employee_name': request.employeeName,
        'line_manager_id': request.lineManagerId,
        'request_time': request.requestTime.toIso8601String(),
        'latitude': request.latitude,
        'longitude': request.longitude,
        'location_name': request.locationName,
        'reason': request.reason,
        'status': request.status.toString().split('.').last,
        'response_time': request.responseTime?.toIso8601String(),
        'response_message': request.responseMessage,
        'is_synced': 1, // This came from Firestore, so it's synced
        'request_type': request.requestType, // Save the request type
      };

      if (existingRequests.isEmpty) {
        // Insert new record
        await _dbHelper.insert('check_out_requests', localData);
      } else {
        // Update existing record
        await _dbHelper.update(
          'check_out_requests',
          localData,
          where: 'id = ?',
          whereArgs: [request.id],
        );
      }
    } catch (e) {
      print("Error saving request locally: $e");
    }
  }

  // Get pending sync requests
  Future<List<Map<String, dynamic>>> getPendingSyncRequests() async {
    try {
      await _ensureTableExists();

      return await _dbHelper.query(
        'check_out_requests',
        where: 'is_synced = ?',
        whereArgs: [0],
      );
    } catch (e) {
      print("Error getting pending sync requests: $e");
      return [];
    }
  }

  Future<List<CheckOutRequest>> getPendingRequestsForManagerWithType(
      String lineManagerId, String requestType) async {
    try {
      await _ensureTableExists();
      List<CheckOutRequest> requests = [];

      // Check online first if possible
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        try {
          final snapshot = await _firestore
              .collection('check_out_requests')
              .where('lineManagerId', isEqualTo: lineManagerId)
              .where('status', isEqualTo: CheckOutRequestStatus.pending.toString().split('.').last)
              .where('requestType', isEqualTo: requestType)
              .orderBy('requestTime', descending: true)
              .get();

          requests = snapshot.docs.map((doc) {
            return CheckOutRequest.fromMap(doc.data(), doc.id);
          }).toList();

          // Also cache these requests locally
          for (var request in requests) {
            await _saveRequestLocally(request);
          }

          return requests;
        } catch (e) {
          print("Error fetching requests from Firestore: $e");
          // Fall back to local data
        }
      }

      // Get from local storage
      final localRequests = await _dbHelper.query(
        'check_out_requests',
        where: 'line_manager_id = ? AND status = ? AND request_type = ?',
        whereArgs: [
          lineManagerId,
          CheckOutRequestStatus.pending.toString().split('.').last,
          requestType
        ],
        orderBy: 'request_time DESC',
      );

      return _mapLocalRequestsToModels(localRequests);
    } catch (e) {
      print("Error getting pending requests with type: $e");
      return [];
    }
  }

// Helper method to map local SQLite records to CheckOutRequest models
  List<CheckOutRequest> _mapLocalRequestsToModels(List<Map<String, dynamic>> localRequests) {
    return localRequests.map((map) {
      // Convert from SQLite format to our model
      final formattedMap = {
        'employeeId': map['employee_id'],
        'employeeName': map['employee_name'],
        'lineManagerId': map['line_manager_id'],
        'requestTime': Timestamp.fromDate(DateTime.parse(map['request_time'] as String)),
        'latitude': map['latitude'],
        'longitude': map['longitude'],
        'locationName': map['location_name'],
        'reason': map['reason'],
        'status': map['status'],
        'responseTime': map['response_time'] != null
            ? Timestamp.fromDate(DateTime.parse(map['response_time'] as String))
            : null,
        'responseMessage': map['response_message'],
        'requestType': map['request_type'] ?? 'check-out', // Default for backward compatibility
      };

      return CheckOutRequest.fromMap(formattedMap, map['id'] as String);
    }).toList();
  }


  // Sync a specific request to Firestore
  Future<bool> syncRequest(Map<String, dynamic> localRequest) async {
    try {
      if (_connectivityService.currentStatus == ConnectionStatus.offline) {
        return false;
      }

      // Format for Firestore
      Map<String, dynamic> firestoreData = {
        'employeeId': localRequest['employee_id'],
        'employeeName': localRequest['employee_name'],
        'lineManagerId': localRequest['line_manager_id'],
        'requestTime': DateTime.parse(localRequest['request_time']),
        'latitude': localRequest['latitude'],
        'longitude': localRequest['longitude'],
        'locationName': localRequest['location_name'],
        'reason': localRequest['reason'],
        'status': localRequest['status'],
        'responseTime': localRequest['response_time'] != null
            ? DateTime.parse(localRequest['response_time'])
            : null,
        'responseMessage': localRequest['response_message'],
        'requestType': localRequest['request_type'] ?? 'check-out', // Default for backward compatibility
      };

      // Convert any DateTime objects to Timestamps
      Map<String, dynamic> firestoreTimestamps = {};
      firestoreData.forEach((key, value) {
        if (value is DateTime) {
          firestoreTimestamps[key] = Timestamp.fromDate(value);
        } else {
          firestoreTimestamps[key] = value;
        }
      });

      // If it has a Firestore ID, update; otherwise, create
      String id = localRequest['id'];
      bool isLocal = id.startsWith('1'); // This checks if it's a timestamp ID we generated

      if (isLocal) {
        // Create new document
        final docRef = await _firestore.collection('check_out_requests').add(firestoreTimestamps);

        // Update local record with Firestore ID
        await _dbHelper.update(
          'check_out_requests',
          {'id': docRef.id, 'is_synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        // Update existing document
        await _firestore.collection('check_out_requests').doc(id).update(firestoreTimestamps);

        // Mark as synced
        await _dbHelper.update(
          'check_out_requests',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      return true;
    } catch (e) {
      print("Error syncing request: $e");
      return false;
    }
  }

  // Sync all pending requests
  Future<bool> syncAllPendingRequests() async {
    try {
      if (_connectivityService.currentStatus == ConnectionStatus.offline) {
        return false;
      }

      final pendingRequests = await getPendingSyncRequests();
      int successCount = 0;

      for (var request in pendingRequests) {
        bool success = await syncRequest(request);
        if (success) successCount++;
      }

      return successCount == pendingRequests.length;
    } catch (e) {
      print("Error syncing all requests: $e");
      return false;
    }
  }
}