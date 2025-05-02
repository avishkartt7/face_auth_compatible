// lib/admin/location_management_view.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/admin/add_edit_location_view.dart';
import 'package:face_auth_compatible/model/location_model.dart';
import 'package:face_auth_compatible/model/location_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
class LocationManagementView extends StatefulWidget {
  const LocationManagementView({Key? key}) : super(key: key);

  @override
  State<LocationManagementView> createState() => _LocationManagementViewState();
}

class _LocationManagementViewState extends State<LocationManagementView> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: accentColor))
          : StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('locations').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: accentColor),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                "Error loading locations: ${snapshot.error}",
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.location_off,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "No locations added yet",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_location_alt),
                    label: const Text("Add First Location"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () => _navigateToAddLocation(),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              DocumentSnapshot doc = snapshot.data!.docs[index];
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              LocationModel location = LocationModel.fromJson(data);
              location.id = doc.id;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: accentColor,
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    location.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        location.address,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Coordinates: ${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Radius: ${location.radius.toStringAsFixed(1)} meters',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: location.isActive,
                        onChanged: (value) => _toggleLocationActive(location.id!, value),
                        activeColor: accentColor,
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: accentColor),
                        onPressed: () => _navigateToEditLocation(location),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDeleteLocation(location.id!, location.name),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddLocation,
        backgroundColor: accentColor,
        child: const Icon(Icons.add_location_alt),
      ),
    );
  }

  void _navigateToAddLocation() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AddEditLocationView(),
      ),
    );
  }

  void _navigateToEditLocation(LocationModel location) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddEditLocationView(location: location),
      ),
    );
  }

  Future<void> _toggleLocationActive(String locationId, bool isActive) async {
    try {
      await FirebaseFirestore.instance.collection('locations').doc(locationId).update({
        'isActive': isActive,
      });

      CustomSnackBar.successSnackBar(
          isActive ? "Location activated" : "Location deactivated"
      );
    } catch (e) {
      CustomSnackBar.errorSnackBar("Error updating location: $e");
    }
  }

  Future<void> _confirmDeleteLocation(String locationId, String locationName) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Location"),
        content: Text("Are you sure you want to delete '$locationName'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ) ?? false;

    if (confirm) {
      setState(() => _isLoading = true);

      try {
        await FirebaseFirestore.instance.collection('locations').doc(locationId).delete();

        setState(() => _isLoading = false);

        if (mounted) {
          CustomSnackBar.successSnackBar("Location deleted successfully");
        }
      } catch (e) {
        setState(() => _isLoading = false);
        CustomSnackBar.errorSnackBar("Error deleting location: $e");
      }
    }
  }
}