// lib/admin/user_management_admin.dart (create this file)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/admin/add_edit_employee_view.dart';
import 'package:firebase_auth/firebase_auth.dart';
class UserManagementAdmin extends StatefulWidget {
  const UserManagementAdmin({Key? key}) : super(key: key);

  @override
  State<UserManagementAdmin> createState() => _UserManagementAdminState();
}

class _UserManagementAdminState extends State<UserManagementAdmin> {
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();
  String? _searchQuery;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search employees...",
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery != null
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _searchQuery = null;
                      _searchController.clear();
                    });
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onSubmitted: (value) {
                setState(() {
                  _searchQuery = value.isNotEmpty ? value : null;
                });
              },
            ),
          ),

          // Employee list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: accentColor))
                : _buildEmployeeList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddEmployee,
        backgroundColor: accentColor,
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildEmployeeList() {
    Query query = FirebaseFirestore.instance.collection('employees');

    // Apply search filter if query exists
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      // Firebase doesn't support case-insensitive search directly
      // For better search, consider using a dedicated search service
      query = query.where('name', isGreaterThanOrEqualTo: _searchQuery!)
          .where('name', isLessThanOrEqualTo: _searchQuery! + '\uf8ff');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: accentColor),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              "Error loading employees: ${snapshot.error}",
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
                  Icons.people_outline,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  _searchQuery != null
                      ? "No employees found matching '$_searchQuery'"
                      : "No employees registered yet",
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_searchQuery != null) ...[
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _searchQuery = null;
                        _searchController.clear();
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                    ),
                    child: const Text("Clear Search"),
                  ),
                ],
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

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: accentColor,
                  child: Text(
                    (data['name'] as String?)?.isNotEmpty == true
                        ? (data['name'] as String).substring(0, 1).toUpperCase()
                        : "?",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  data['name'] ?? "Unnamed Employee",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      "PIN: ${data['pin'] ?? 'Not set'}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Designation: ${data['designation'] ?? 'Not set'}",
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Department: ${data['department'] ?? 'Not set'}",
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildStatusChip(
                          "Face Registered",
                          data['faceRegistered'] == true,
                        ),
                        const SizedBox(width: 8),
                        _buildStatusChip(
                          "Profile Complete",
                          data['profileCompleted'] == true,
                        ),
                      ],
                    ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: accentColor),
                      onPressed: () => _navigateToEditEmployee(doc.id, data),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _confirmDeleteEmployee(doc.id, data['name'] ?? 'this employee'),
                    ),
                  ],
                ),
                onTap: () => _showEmployeeDetails(doc.id, data),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusChip(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.withOpacity(0.2) : Colors.grey.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isActive ? Icons.check_circle : Icons.cancel,
            color: isActive ? Colors.green : Colors.grey,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive ? Colors.green.shade800 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToAddEmployee() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AddEditEmployeeView(),
      ),
    );
  }

  void _navigateToEditEmployee(String employeeId, Map<String, dynamic> data) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddEditEmployeeView(
          employeeId: employeeId,
          employeeData: data,
        ),
      ),
    );
  }

  void _showEmployeeDetails(String employeeId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(data['name'] ?? 'Employee Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('PIN', data['pin'] ?? 'Not set'),
              _buildDetailRow('Designation', data['designation'] ?? 'Not set'),
              _buildDetailRow('Department', data['department'] ?? 'Not set'),
              _buildDetailRow('Email', data['email'] ?? 'Not set'),
              _buildDetailRow('Phone', data['phone'] ?? 'Not set'),
              _buildDetailRow('Country', data['country'] ?? 'Not set'),
              _buildDetailRow('Birthdate', data['birthdate'] ?? 'Not set'),
              _buildDetailRow('Face Registered', data['faceRegistered'] == true ? 'Yes' : 'No'),
              _buildDetailRow('Profile Completed', data['profileCompleted'] == true ? 'Yes' : 'No'),
              _buildDetailRow('Registration Completed', data['registrationCompleted'] == true ? 'Yes' : 'No'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _navigateToEditEmployee(employeeId, data);
            },
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteEmployee(String employeeId, String employeeName) async {
    bool confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Employee"),
        content: Text("Are you sure you want to delete '$employeeName'? This will permanently remove all their data, including attendance records."),
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
        // Delete employee document
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(employeeId)
            .delete();

        // Delete attendance records (in a subcollection)
        final attendanceSnapshot = await FirebaseFirestore.instance
            .collection('employees')
            .doc(employeeId)
            .collection('attendance')
            .get();

        final batch = FirebaseFirestore.instance.batch();
        for (var doc in attendanceSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        setState(() => _isLoading = false);

        if (mounted) {
          CustomSnackBar.successSnackBar("Employee deleted successfully");
        }
      } catch (e) {
        setState(() => _isLoading = false);
        CustomSnackBar.errorSnackBar("Error deleting employee: $e");
      }
    }
  }
}