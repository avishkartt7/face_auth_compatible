// lib/admin/add_edit_location_view.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/model/location_model.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:face_auth_compatible/model/location_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
class AddEditLocationView extends StatefulWidget {
  final LocationModel? location;

  const AddEditLocationView({Key? key, this.location}) : super(key: key);

  @override
  State<AddEditLocationView> createState() => _AddEditLocationViewState();
}

class _AddEditLocationViewState extends State<AddEditLocationView> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _radiusController = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isActive = true;
  bool _isLoading = false;
  bool _isEditMode = false;

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(25.2048, 55.2708), // Dubai by default
    zoom: 12,
  );

  @override
  void initState() {
    super.initState();

    if (widget.location != null) {
      _isEditMode = true;
      _nameController.text = widget.location!.name;
      _addressController.text = widget.location!.address;
      _latitudeController.text = widget.location!.latitude.toString();
      _longitudeController.text = widget.location!.longitude.toString();
      _radiusController.text = widget.location!.radius.toString();
      _isActive = widget.location!.isActive;

      _initialCameraPosition = CameraPosition(
        target: LatLng(widget.location!.latitude, widget.location!.longitude),
        zoom: 15,
      );

      _updateMarkerAndCircle(
        LatLng(widget.location!.latitude, widget.location!.longitude),
        widget.location!.radius,
      );
    } else {
      // Default radius for new locations
      _radiusController.text = "200.0";
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _radiusController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _latitudeController.text = position.latitude.toString();
        _longitudeController.text = position.longitude.toString();
        _initialCameraPosition = CameraPosition(
          target: LatLng(position.latitude, position.longitude),
          zoom: 15,
        );

        _updateMarkerAndCircle(
          LatLng(position.latitude, position.longitude),
          double.parse(_radiusController.text),
        );
      });

      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(_initialCameraPosition),
      );
    } catch (e) {
      CustomSnackBar.errorSnackBar("Error getting current location: $e");
    }
  }

  void _updateMarkerAndCircle(LatLng position, double radius) {
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('locationMarker'),
          position: position,
          draggable: true,
          onDragEnd: (newPosition) {
            setState(() {
              _latitudeController.text = newPosition.latitude.toString();
              _longitudeController.text = newPosition.longitude.toString();
              _updateMarkerAndCircle(newPosition, radius);
            });
          },
        ),
      };

      _circles = {
        Circle(
          circleId: const CircleId('geofenceCircle'),
          center: position,
          radius: radius,
          fillColor: accentColor.withOpacity(0.2),
          strokeColor: accentColor,
          strokeWidth: 2,
        ),
      };
    });
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;

    if (_isEditMode || _latitudeController.text.isNotEmpty) {
      double lat = double.parse(_latitudeController.text);
      double lng = double.parse(_longitudeController.text);
      double radius = double.parse(_radiusController.text);

      _updateMarkerAndCircle(LatLng(lat, lng), radius);
    }
  }

  void _onMapTap(LatLng position) {
    setState(() {
      _latitudeController.text = position.latitude.toString();
      _longitudeController.text = position.longitude.toString();
      _updateMarkerAndCircle(
        position,
        double.parse(_radiusController.text),
      );
    });
  }

  Future<void> _saveLocation() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final LocationModel location = LocationModel(
        id: _isEditMode ? widget.location!.id : null,
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        latitude: double.parse(_latitudeController.text),
        longitude: double.parse(_longitudeController.text),
        radius: double.parse(_radiusController.text),
        isActive: _isActive,
      );

      if (_isEditMode) {
        // Update existing location
        await FirebaseFirestore.instance
            .collection('locations')
            .doc(location.id)
            .update(location.toJson());

        CustomSnackBar.successSnackBar("Location updated successfully");
      } else {
        // Add new location
        await FirebaseFirestore.instance
            .collection('locations')
            .add(location.toJson());

        CustomSnackBar.successSnackBar("Location added successfully");
      }

      setState(() => _isLoading = false);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar("Error saving location: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(_isEditMode ? "Edit Location" : "Add Location"),
          backgroundColor: scaffoldTopGradientClr,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: accentColor))
            : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
    child: Form(
    key: _formKey,
    child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
    // Map for selecting location
    Container(
    height: 250,
    decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.grey.shade300),
    ),
    child: ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: GoogleMap(
    initialCameraPosition: _initialCameraPosition,
    onMapCreated: _onMapCreated,
    markers: _markers,
    circles: _circles,
    onTap: _onMapTap,
    myLocationEnabled: true,
    myLocationButtonEnabled: true,
    zoomControlsEnabled: true,
    ),
    ),
    ),

    const SizedBox(height: 20),

    // Location name
    TextFormField(
    controller: _nameController,
    decoration: const InputDecoration(
    labelText: "Location Name",
    prefixIcon: Icon(Icons.business),
    border: OutlineInputBorder(),
    ),
    validator: (value) {
    if (value == null || value.trim().isEmpty) {
    return "Please enter a location name";
    }
    return null;
    },
    ),

    const SizedBox(height: 16),

    // Address
    TextFormField(
    controller: _addressController,
    decoration: const InputDecoration(
    labelText: "Address",
    prefixIcon: Icon(Icons.location_city),
    border: OutlineInputBorder(),
    ),
    validator: (value) {
    if (value == null || value.trim().isEmpty) {
    return "Please enter an address";
    }
    return null;
    },
    ),

    const SizedBox(height: 16),

    // Coordinates row
    Row(
    children: [
    // Latitude
    Expanded(
    child: TextFormField(
    controller: _latitudeController,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: const InputDecoration(
    labelText: "Latitude",
    prefixIcon: Icon(Icons.my_location),
    border: OutlineInputBorder(),
    ),
    validator: (value) {
    if (value == null || value.isEmpty) {
    return "Required";
    }
    if (double.tryParse(value) == null) {
    return "Invalid number";
    }
    return null;
    },
    onChanged: (value) {
    if (value.isNotEmpty && _longitudeController.text.isNotEmpty) {
    try {
    double lat = double.parse(value);
    double lng = double.parse(_longitudeController.text);
    double radius = double.parse(_radiusController.text);

    _updateMarkerAndCircle(LatLng(lat, lng), radius);
    } catch (e) {
    // Ignore parsing errors during typing
    }
    }
    },
    ),
    ),

    const SizedBox(width: 8),

    // Longitude
    Expanded(
    child: TextFormField(
      // lib/admin/add_edit_location_view.dart (continued)
      controller: _longitudeController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: "Longitude",
        prefixIcon: Icon(Icons.my_location),
        border: OutlineInputBorder(),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return "Required";
        }
        if (double.tryParse(value) == null) {
          return "Invalid number";
        }
        return null;
      },
      onChanged: (value) {
        if (value.isNotEmpty && _latitudeController.text.isNotEmpty) {
          try {
            double lat = double.parse(_latitudeController.text);
            double lng = double.parse(value);
            double radius = double.parse(_radiusController.text);

            _updateMarkerAndCircle(LatLng(lat, lng), radius);
          } catch (e) {
            // Ignore parsing errors during typing
          }
        }
      },
    ),
    ),
    ],
    ),

      const SizedBox(height: 16),

      // Radius
      TextFormField(
        controller: _radiusController,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: "Geofence Radius (meters)",
          prefixIcon: const Icon(Icons.radio_button_checked),
          border: const OutlineInputBorder(),
          suffixText: "meters",
          suffixStyle: TextStyle(color: Colors.grey.shade600),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return "Required";
          }
          final radius = double.tryParse(value);
          if (radius == null) {
            return "Invalid number";
          }
          if (radius <= 0) {
            return "Radius must be positive";
          }
          return null;
        },
        onChanged: (value) {
          if (value.isNotEmpty &&
              _latitudeController.text.isNotEmpty &&
              _longitudeController.text.isNotEmpty) {
            try {
              double lat = double.parse(_latitudeController.text);
              double lng = double.parse(_longitudeController.text);
              double radius = double.parse(value);

              if (radius > 0) {
                _updateMarkerAndCircle(LatLng(lat, lng), radius);
              }
            } catch (e) {
              // Ignore parsing errors during typing
            }
          }
        },
      ),

      const SizedBox(height: 16),

      // Active status
      SwitchListTile(
        title: const Text("Active"),
        subtitle: const Text("Location is available for check-in"),
        value: _isActive,
        onChanged: (value) {
          setState(() {
            _isActive = value;
          });
        },
        activeColor: accentColor,
      ),

      const SizedBox(height: 24),

      // Save button
      SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: _saveLocation,
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.white,
          ),
          child: Text(
            _isEditMode ? "Update Location" : "Add Location",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    ],
    ),
    ),
        ),
    );
  }
}