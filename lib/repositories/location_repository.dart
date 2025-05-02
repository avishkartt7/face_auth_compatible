// lib/repositories/location_repository.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/model/location_model.dart';
import 'package:face_auth_compatible/services/database_helper.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';

class LocationRepository {
  final DatabaseHelper _dbHelper;
  final FirebaseFirestore _firestore;
  final ConnectivityService _connectivityService;

  LocationRepository({
    required DatabaseHelper dbHelper,
    FirebaseFirestore? firestore,
    required ConnectivityService connectivityService,
  }) : _dbHelper = dbHelper,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _connectivityService = connectivityService;

  // Fetch locations with offline support
  Future<List<LocationModel>> getActiveLocations() async {
    try {
      // If online, try to fetch from Firestore and update local cache
      if (_connectivityService.currentStatus == ConnectionStatus.online) {
        try {
          final QuerySnapshot snapshot = await _firestore
              .collection('locations')
              .where('isActive', isEqualTo: true)
              .get();

          // Clear existing cached locations
          await _dbHelper.delete('locations');

          // Store the new locations
          for (var doc in snapshot.docs) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            LocationModel location = LocationModel.fromJson(data);
            location.id = doc.id;

            await _dbHelper.insert('locations', {
              'id': location.id,
              'name': location.name,
              'address': location.address,
              'latitude': location.latitude,
              'longitude': location.longitude,
              'radius': location.radius,
              'is_active': location.isActive ? 1 : 0,
              'last_updated': DateTime.now().millisecondsSinceEpoch,
            });
          }

          // Convert to LocationModel objects
          return snapshot.docs.map((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            LocationModel location = LocationModel.fromJson(data);
            location.id = doc.id;
            return location;
          }).toList();
        } catch (e) {
          // If online fetch fails, fall back to cached data
          print('Error fetching online locations: $e');
        }
      }

      // Read from local database
      final List<Map<String, dynamic>> maps = await _dbHelper.query(
        'locations',
        where: 'is_active = ?',
        whereArgs: [1],
      );

      if (maps.isNotEmpty) {
        return maps.map((map) {
          return LocationModel(
            id: map['id'],
            name: map['name'],
            address: map['address'],
            latitude: map['latitude'],
            longitude: map['longitude'],
            radius: map['radius'],
            isActive: map['is_active'] == 1,
          );
        }).toList();
      }

      // If no cached data, return default location
      return [
        LocationModel(
          id: 'default',
          name: 'Central Plaza',
          address: 'DIP 1, Street 72, Dubai',
          latitude: 24.985454,
          longitude: 55.175509,
          radius: 200.0,
          isActive: true,
        ),
      ];
    } catch (e) {
      print('Error getting active locations: $e');

      // Return default location on error
      return [
        LocationModel(
          id: 'default',
          name: 'Central Plaza',
          address: 'DIP 1, Street 72, Dubai',
          latitude: 24.985454,
          longitude: 55.175509,
          radius: 200.0,
          isActive: true,
        ),
      ];
    }
  }
}