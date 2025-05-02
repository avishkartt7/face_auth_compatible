// lib/utils/geofence_util.dart (updated)

import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/model/location_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:face_auth_compatible/model/location_model.dart';

class GeofenceUtil {
  // Cache key
  static const String _cachedLocationsKey = 'cached_locations';
  static const Duration _cacheExpiry = Duration(hours: 1);

  // Fallback location in case no locations are available
  // Central Plaza, DIP 1, Street 72, Dubai as fallback
  static const double defaultOfficeLatitude = 24.985454;
  static const double defaultOfficeLongitude = 55.175509;
  static const double defaultGeofenceRadius = 200.0;

  // Property for backward compatibility
  static double get officeLatitude => defaultOfficeLatitude;
  static double get officeLongitude => defaultOfficeLongitude;
  static double get geofenceRadius => defaultGeofenceRadius;

  // Check location permissions
  static Future<bool> checkLocationPermission(BuildContext context) async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Location services are not enabled
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location services are disabled. Please enable the services'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    // Check location permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // Permissions are denied
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are denied'),
            backgroundColor: Colors.red,
          ),
        );
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Permissions are permanently denied
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location permissions are permanently denied, please enable them in app settings',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    // Permissions are granted
    return true;
  }

  // Get current position
  static Future<Position?> getCurrentPosition() async {
    try {
      // Set accuracy to best for most precise results
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return null;
    }
  }

  // Fetch all active locations from Firebase (or from cache if available)
  static Future<List<LocationModel>> getActiveLocations(BuildContext context) async {
    try {
      // Try to get from cache first if not expired
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? cachedData = prefs.getString(_cachedLocationsKey);
      final int? cacheTime = prefs.getInt('${_cachedLocationsKey}_time');

      final now = DateTime.now().millisecondsSinceEpoch;
      final bool cacheExpired = cacheTime == null ||
          now - cacheTime > _cacheExpiry.inMilliseconds;

      // Use cache if available and not expired
      if (!cacheExpired && cachedData != null) {
        final List<dynamic> decoded = json.decode(cachedData);
        return decoded
            .map((e) => LocationModel.fromJson(e))
            .toList();
      }

      // Otherwise fetch from Firebase
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('locations')
          .where('isActive', isEqualTo: true)
          .get();

      if (snapshot.docs.isEmpty) {
        // No locations in database, return default location
        return [
          LocationModel(
            id: 'default',
            name: 'Central Plaza',
            address: 'DIP 1, Street 72, Dubai',
            latitude: defaultOfficeLatitude,
            longitude: defaultOfficeLongitude,
            radius: defaultGeofenceRadius,
            isActive: true,
          ),
        ];
      }

      // Convert to LocationModel list
      List<LocationModel> locations = snapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        LocationModel location = LocationModel.fromJson(data);
        location.id = doc.id;
        return location;
      }).toList();

      // Cache the results
      await prefs.setString(_cachedLocationsKey, json.encode(
          locations.map((e) => {...e.toJson(), 'id': e.id}).toList()
      ));
      await prefs.setInt('${_cachedLocationsKey}_time', now);

      return locations;
    } catch (e) {
      debugPrint('Error fetching locations: $e');

      // Fallback to default location in case of error
      return [
        LocationModel(
          id: 'default',
          name: 'Central Plaza',
          address: 'DIP 1, Street 72, Dubai',
          latitude: defaultOfficeLatitude,
          longitude: defaultOfficeLongitude,
          radius: defaultGeofenceRadius,
          isActive: true,
        ),
      ];
    }
  }

  // Check if user is within any geofence
  static Future<Map<String, dynamic>> checkGeofenceStatus(BuildContext context) async {
    bool hasPermission = await checkLocationPermission(context);
    if (!hasPermission) {
      return {
        'withinGeofence': false,
        'location': null,
        'distance': null,
      };
    }

    Position? currentPosition = await getCurrentPosition();
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to get current location'),
          backgroundColor: Colors.red,
        ),
      );
      return {
        'withinGeofence': false,
        'location': null,
        'distance': null,
      };
    }

    // Debug prints
    debugPrint('LOCATION CHECK:');
    debugPrint('Current position: ${currentPosition.latitude}, ${currentPosition.longitude}');

    // Get all active locations
    List<LocationModel> locations = await getActiveLocations(context);

    // Find closest location and check if within radius
    LocationModel? closestLocation;
    double? shortestDistance;
    bool withinAnyGeofence = false;

    for (var location in locations) {
      double distanceInMeters = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        location.latitude,
        location.longitude,
      );

      debugPrint('${location.name}: ${distanceInMeters.toStringAsFixed(2)} meters');

      // Update closest location if this is closer than previous
      if (shortestDistance == null || distanceInMeters < shortestDistance) {
        shortestDistance = distanceInMeters;
        closestLocation = location;
      }

      // Check if within this location's radius
      if (distanceInMeters <= location.radius) {
        withinAnyGeofence = true;
        // If within radius, prioritize this location
        closestLocation = location;
        shortestDistance = distanceInMeters;
        break; // Optimization: we found a matching location, no need to check others
      }
    }

    // Return result
    return {
      'withinGeofence': withinAnyGeofence,
      'location': closestLocation,
      'distance': shortestDistance,
    };
  }

  // Legacy: Check if user is within geofence (for backward compatibility)
  static Future<bool> isWithinGeofence(BuildContext context) async {
    Map<String, dynamic> status = await checkGeofenceStatus(context);
    return status['withinGeofence'] as bool;
  }

  // Legacy: Get distance to office (for backward compatibility)
  static Future<double?> getDistanceToOffice(BuildContext context) async {
    Map<String, dynamic> status = await checkGeofenceStatus(context);
    return status['distance'] as double?;
  }

  // Get full debug info for troubleshooting
  static Future<Map<String, dynamic>> getDebugInfo(BuildContext context) async {
    Position? position = await getCurrentPosition();
    List<LocationModel> locations = await getActiveLocations(context);

    if (position == null) {
      return {
        'error': 'Unable to get current position',
        'within_geofence': false,
        'distance': null,
      };
    }

    Map<String, dynamic> result = {
      'current_latitude': position.latitude,
      'current_longitude': position.longitude,
      'locations': locations.map((loc) => {
        'id': loc.id,
        'name': loc.name,
        'latitude': loc.latitude,
        'longitude': loc.longitude,
        'radius': loc.radius,
      }).toList(),
    };

    // Calculate distances to all locations
    for (var i = 0; i < locations.length; i++) {
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        locations[i].latitude,
        locations[i].longitude,
      );

      bool withinThisGeofence = distance <= locations[i].radius;

      result['distance_to_${locations[i].id}'] = distance;
      result['within_geofence_${locations[i].id}'] = withinThisGeofence;

      // For backward compatibility
      if (i == 0) {
        result['distance'] = distance;
        result['office_latitude'] = locations[i].latitude;
        result['office_longitude'] = locations[i].longitude;
        result['geofence_radius'] = locations[i].radius;
        result['within_geofence'] = withinThisGeofence;
      }
    }

    return result;
  }
}