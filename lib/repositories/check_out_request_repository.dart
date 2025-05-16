import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/model/check_out_request_model.dart';
import 'package:face_auth_compatible/services/database_helper.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';
import 'package:flutter/foundation.dart'; // Add for debugPrint
import 'package:cloud_functions/cloud_functions.dart'; // Added missing import

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
      debugPrint("Created check_out_requests table");
    } else {
      // Check if requestType column exists, add it if it doesn't
      try {
        await db.rawQuery("SELECT request_type FROM check_out_requests LIMIT 1");
      } catch (e) {
        // Column doesn't exist, add it
        await db.execute(
            "ALTER TABLE check_out_requests ADD COLUMN request_type TEXT DEFAULT 'check-out'");
        debugPrint("Added request_type column to existing table");
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

      // Log request details for debugging
      debugPrint("REPO: Creating ${request.requestType} request from ${request.employeeName} to manager ${request.lineManagerId}");
      debugPrint("REPO: Reason: ${request.reason}");
      debugPrint("REPO: Location: ${request.locationName}");

      // If online, try to save to Firestore first
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        try {
          // Create a document in the check_out_requests collection
          final docRef = await _firestore.collection('check_out_requests').add(request.toMap());
          remoteId = docRef.id;
          debugPrint("REPO: Saved request to Firestore with ID: $remoteId");

          // Also try to notify the manager directly
          await _sendDirectManagerNotification(request);
        } catch (e) {
          debugPrint("REPO: Error saving request to Firestore: $e");
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
      debugPrint("REPO: Saved request locally with ID: ${remoteId ?? localId}");

      return true;
    } catch (e) {
      debugPrint("REPO: Error creating request: $e");
      return false;
    }
  }

  // Get all pending requests for a specific line manager
  Future<List<CheckOutRequest>> getPendingRequestsForManager(String lineManagerId) async {
    try {
      await _ensureTableExists();
      List<CheckOutRequest> requests = [];

      // Prepare different formats of manager ID to check
      List<String> possibleManagerIds = [
        lineManagerId,
        lineManagerId.startsWith('EMP') ? lineManagerId.substring(3) : 'EMP${lineManagerId}',
      ];

      debugPrint("REPO: Checking pending requests for manager IDs: $possibleManagerIds");

      // Check online first if possible
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        try {
          // Try each possible manager ID format
          for (String managerId in possibleManagerIds) {
            final snapshot = await _firestore
                .collection('check_out_requests')
                .where('lineManagerId', isEqualTo: managerId)
                .where('status', isEqualTo: CheckOutRequestStatus.pending.toString().split('.').last)
                .orderBy('requestTime', descending: true)
                .get();

            if (snapshot.docs.isNotEmpty) {
              debugPrint("REPO: Found ${snapshot.docs.length} pending requests for manager ID: $managerId");

              final requestsFromSnapshot = snapshot.docs.map((doc) {
                return CheckOutRequest.fromMap(doc.data(), doc.id);
              }).toList();

              requests.addAll(requestsFromSnapshot);

              // Cache these requests locally
              for (var request in requestsFromSnapshot) {
                await _saveRequestLocally(request);
              }
            }
          }

          // If requests were found online, return them
          if (requests.isNotEmpty) {
            // Remove any duplicates by ID
            final uniqueRequests = <String, CheckOutRequest>{};
            for (var request in requests) {
              uniqueRequests[request.id] = request;
            }

            return uniqueRequests.values.toList();
          }
        } catch (e) {
          debugPrint("REPO: Error fetching requests from Firestore: $e");
          // Fall back to local data
        }
      }

      // Get from local storage, trying each possible manager ID
      List<Map<String, dynamic>> localRequests = [];

      for (String managerId in possibleManagerIds) {
        final managerRequests = await _dbHelper.query(
          'check_out_requests',
          where: 'line_manager_id = ? AND status = ?',
          whereArgs: [managerId, CheckOutRequestStatus.pending.toString().split('.').last],
          orderBy: 'request_time DESC',
        );

        if (managerRequests.isNotEmpty) {
          debugPrint("REPO: Found ${managerRequests.length} local pending requests for manager ID: $managerId");
          localRequests.addAll(managerRequests);
        }
      }

      // Convert local requests to CheckOutRequest objects
      final requestsFromLocal = localRequests.map((map) {
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

      if (requestsFromLocal.isNotEmpty) {
        // Remove any duplicates by ID
        final uniqueRequests = <String, CheckOutRequest>{};
        for (var request in requestsFromLocal) {
          uniqueRequests[request.id] = request;
        }

        return uniqueRequests.values.toList();
      }

      // If no requests found, return empty list
      return [];
    } catch (e) {
      debugPrint("REPO: Error getting pending requests: $e");
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
          debugPrint("Error fetching requests from Firestore: $e");
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
      debugPrint("Error getting employee requests: $e");
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
      debugPrint("Error responding to request: $e");
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
      debugPrint("Error saving request locally: $e");
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
      debugPrint("Error getting pending sync requests: $e");
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
          debugPrint("Error fetching requests from Firestore: $e");
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
      debugPrint("Error getting pending requests with type: $e");
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
      debugPrint("Error syncing request: $e");
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
      debugPrint("Error syncing all requests: $e");
      return false;
    }
  }

  // Add a method to directly notify the manager as a backup
  Future<void> _sendDirectManagerNotification(CheckOutRequest request) async {
    try {
      // Only continue if we're online
      if (_connectivityService.currentStatus == ConnectionStatus.offline) {
        return;
      }

      // Format the request type for display - ensuring proper capitalization
      String displayType = request.requestType == 'check-in' ? 'Check-In' : 'Check-Out';

      debugPrint("REPO: Sending notification to manager ${request.lineManagerId} for ${request.requestType} request");

      // Try multiple methods for reliability

      // 1. First try topic-based notifications for all formats of manager ID
      List<String> managerTopics = [
        'manager_${request.lineManagerId}',
        request.lineManagerId.startsWith('EMP')
            ? 'manager_${request.lineManagerId.substring(3)}'
            : 'manager_EMP${request.lineManagerId}',
        'all_managers'
      ];

      // Send to each topic
      for (String topic in managerTopics) {
        try {
          await _firestore.collection('notifications').add({
            'topic': topic,
            'title': 'New $displayType Request',
            'body': '${request.employeeName} has requested to ${request.requestType.replaceAll('-', ' ')} from an offsite location.',
            'data': {
              'type': 'new_check_out_request',
              'requestId': request.id,
              'employeeId': request.employeeId,
              'employeeName': request.employeeName,
              'locationName': request.locationName,
              'requestType': request.requestType,
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            },
            'android': {
              'priority': 'high',
              'notification': {
                'sound': 'default',
                'priority': 'high',
                'channel_id': 'check_requests_channel'
              }
            },
            'apns': {
              'payload': {
                'aps': {
                  'sound': 'default',
                  'badge': 1,
                  'content_available': true,
                  'interruption_level': 'time-sensitive'
                }
              }
            },
            'sentAt': FieldValue.serverTimestamp(),
          });

          debugPrint("REPO: Sent notification to topic: $topic");
        } catch (e) {
          debugPrint("REPO: Error sending topic notification to $topic: $e");
        }
      }

      // 2. Try to find the manager's FCM token directly (both formats)
      List<String> managerIds = [
        request.lineManagerId,
        request.lineManagerId.startsWith('EMP')
            ? request.lineManagerId.substring(3)
            : 'EMP${request.lineManagerId}'
      ];

      for (String managerId in managerIds) {
        try {
          final tokenDoc = await _firestore
              .collection('fcm_tokens')
              .doc(managerId)
              .get();

          if (tokenDoc.exists) {
            String? token = tokenDoc.data()?['token'];
            if (token != null) {
              // Send direct notification with token
              await _firestore.collection('notifications').add({
                'token': token,
                'title': 'New $displayType Request',
                'body': '${request.employeeName} has requested to ${request.requestType.replaceAll('-', ' ')} from an offsite location.',
                'data': {
                  'type': 'new_check_out_request',
                  'requestId': request.id,
                  'employeeId': request.employeeId,
                  'employeeName': request.employeeName,
                  'locationName': request.locationName,
                  'requestType': request.requestType,
                  'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                  'fromNotificationTap': 'true',
                },
                'android': {
                  'priority': 'high',
                  'notification': {
                    'sound': 'default',
                    'priority': 'high',
                    'channel_id': 'check_requests_channel'
                  }
                },
                'apns': {
                  'payload': {
                    'aps': {
                      'sound': 'default',
                      'badge': 1,
                      'content_available': true,
                      'interruption_level': 'time-sensitive'
                    }
                  }
                },
                'sentAt': FieldValue.serverTimestamp(),
              });

              debugPrint("REPO: Sent direct notification to manager $managerId with token");
            }
          }
        } catch (e) {
          debugPrint("REPO: Error sending direct notification to manager $managerId: $e");
        }
      }

      // 3. Try Cloud Function as a fallback
      try {
        // Use the Cloud Functions API - this part was causing errors
        final callable = FirebaseFunctions.instance.httpsCallable(
          'sendManagerNotification',
        );

        await callable.call({
          'managerId': request.lineManagerId,
          'employeeName': request.employeeName,
          'requestId': request.id,
          'requestType': request.requestType,
        });

        debugPrint("REPO: Notification sent via Cloud Function");
      } catch (e) {
        debugPrint("REPO: Error sending notification via Cloud Function: $e");
      }

      debugPrint("REPO: All notification methods attempted for manager ${request.lineManagerId}");

      // 4. Add a notification record to a dedicated collection for reliability
      try {
        await _firestore.collection('pending_notifications').add({
          'targetId': request.lineManagerId,
          'title': 'New $displayType Request',
          'body': '${request.employeeName} has requested to ${request.requestType.replaceAll('-', ' ')} from an offsite location.',
          'data': {
            'type': 'new_check_out_request',
            'requestId': request.id,
            'employeeId': request.employeeId,
            'employeeName': request.employeeName,
            'locationName': request.locationName,
            'requestType': request.requestType,
          },
          'sent': false,
          'createdAt': FieldValue.serverTimestamp(),
          'retryCount': 0,
        });
      } catch (e) {
        debugPrint("REPO: Error creating pending notification record: $e");
      }
    } catch (e) {
      debugPrint("REPO: Error in send notification process: $e");
    }
  }
}