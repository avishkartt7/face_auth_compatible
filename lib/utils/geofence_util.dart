// lib/utils/geofence_util.dart

import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';

class GeofenceUtil {
  // Office coordinates (Central Plaza, DIP 1, Street 72, Dubai)
  static const double officeLatitude = 24.985454;
  static const double officeLongitude = 55.175509;

  // Geofence radius in meters
  static const double geofenceRadius = 200.0; // Increased for better testing

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
      LocationSettings locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      );

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return null;
    }
  }

  // Check if user is within geofence
  static Future<bool> isWithinGeofence(BuildContext context) async {
    bool hasPermission = await checkLocationPermission(context);
    if (!hasPermission) {
      return false;
    }

    Position? currentPosition = await getCurrentPosition();
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to get current location'),
          backgroundColor: Colors.red,
        ),
      );
      return false;
    }

    // Debug prints
    debugPrint('LOCATION CHECK:');
    debugPrint('Current position: ${currentPosition.latitude}, ${currentPosition.longitude}');
    debugPrint('Office position: $officeLatitude, $officeLongitude');

    // Calculate the distance
    double distanceInMeters = Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      officeLatitude,
      officeLongitude,
    );

    debugPrint('Distance to office: $distanceInMeters meters');
    debugPrint('Geofence radius: $geofenceRadius meters');

    return distanceInMeters <= geofenceRadius;
  }

  // Get distance to office
  static Future<double?> getDistanceToOffice(BuildContext context) async {
    bool hasPermission = await checkLocationPermission(context);
    if (!hasPermission) {
      return null;
    }

    Position? currentPosition = await getCurrentPosition();
    if (currentPosition == null) {
      return null;
    }

    return Geolocator.distanceBetween(
      currentPosition.latitude,
      currentPosition.longitude,
      officeLatitude,
      officeLongitude,
    );
  }

  // Get full debug info for troubleshooting
  static Future<Map<String, dynamic>> getDebugInfo(BuildContext context) async {
    Position? position = await getCurrentPosition();

    if (position == null) {
      return {
        'error': 'Unable to get current position',
        'within_geofence': false,
        'distance': null,
      };
    }

    double distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      officeLatitude,
      officeLongitude,
    );

    return {
      'current_latitude': position.latitude,
      'current_longitude': position.longitude,
      'office_latitude': officeLatitude,
      'office_longitude': officeLongitude,
      'distance': distance,
      'geofence_radius': geofenceRadius,
      'within_geofence': distance <= geofenceRadius,
    };
  }
}