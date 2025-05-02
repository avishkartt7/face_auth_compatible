// lib/admin/add_edit_employee_view.dart (create this file)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
class AddEditEmployeeView extends StatefulWidget {
  final String? employeeId;
  final Map<String, dynamic>? employeeData;

  const AddEditEmployeeView({
    Key? key,
    this.employeeId,
    this.employeeData,
  }) : super(key: key);

  @override
  State<AddEditEmployeeView> createState() => _AddEditEmployeeViewState();
}

class _AddEditEmployeeViewState extends State<AddEditEmployeeView> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _designationController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _birthdateController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  bool _isEditMode = false;
  bool _isLoading = false;
  bool _generateRandomPin = true;

  @override
  void initState() {
    super.initState();

    if (widget.employeeId != null && widget.employeeData != null) {
      _isEditMode = true;
      _loadEmployeeData();
      _generateRandomPin = false;
    } else {
      // Generate a random PIN for new employees
      _generatePin();
    }
  }

  void _loadEmployeeData() {
    _nameController.text = widget.employeeData!['name'] ?? '';
    _designationController.text = widget.employeeData!['designation'] ?? '';
    _departmentController.text = widget.employeeData!['department'] ?? '';
    _emailController.text = widget.employeeData!['email'] ?? '';
    _phoneController.text = widget.employeeData!['phone'] ?? '';
    _countryController.text = widget.employeeData!['country'] ?? '';
    _birthdateController.text = widget.employeeData!['birthdate'] ?? '';
    _pinController.text = widget.employeeData!['pin'] ?? '';
  }

  void _generatePin() {
    // Generate a random 4-digit PIN
    final random = Random();
    final pin = (1000 + random.nextInt(9000)).toString(); // Ensures 4 digits
    _pinController.text = pin;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _designationController.dispose();
    _departmentController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _countryController.dispose();
    _birthdateController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Check if PIN is already used by another employee
      if (_isEditMode) {
        // Only check for duplicates if PIN has changed
        final originalPin = widget.employeeData!['pin'];
        if (_pinController.text != originalPin) {
          await _checkDuplicatePin();
        }
      } else {
        await _checkDuplicatePin();
      }

      // Prepare employee data
      Map<String, dynamic> employeeData = {
        'name': _nameController.text.trim(),
        'designation': _designationController.text.trim(),
        'department': _departmentController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'country': _countryController.text.trim(),
        'birthdate': _birthdateController.text.trim(),
        'pin': _pinController.text.trim(),
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      if (!_isEditMode) {
        // Add defaults for new employees
        employeeData.addAll({

          'profileCompleted': false,
          'faceRegistered': false,
          'registrationCompleted': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (_isEditMode) {
        // Update existing employee
        await FirebaseFirestore.instance
            .collection('employees')
            .doc(widget.employeeId)
            .update(employeeData);

        CustomSnackBar.successSnackBar("Employee updated successfully");
      } else {
        // Add new employee
        await FirebaseFirestore.instance
            .collection('employees')
            .add(employeeData);

        CustomSnackBar.successSnackBar("Employee added successfully");
      }

      setState(() => _isLoading = false);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar("Error saving employee: $e");
    }
  }

  Future<void> _checkDuplicatePin() async {
    final pin = _pinController.text.trim();

    // Check if this PIN is already used
    final querySnapshot = await FirebaseFirestore.instance
        .collection('employees')
        .where('pin', isEqualTo: pin)
        .get();

    // If editing, exclude the current employee
    final duplicates = querySnapshot.docs.where((doc) =>
    !_isEditMode || doc.id != widget.employeeId).toList();

    if (duplicates.isNotEmpty) {
      throw Exception("This PIN is already assigned to another employee. Please use a different PIN.");
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: accentColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _birthdateController.text = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? "Edit Employee" : "Add New Employee"),
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
              // Name field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: "Full Name *",
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Please enter employee's name";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // PIN field with generate button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: "PIN (4 digits) *",
                        prefixIcon: Icon(Icons.pin),
                        border: OutlineInputBorder(),
                        counterText: "",
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return "Please enter a PIN";
                        }
                        if (value.length != 4) {
                          return "PIN must be 4 digits";
                        }
                        if (int.tryParse(value) == null) {
                          return "PIN must contain only numbers";
                        }
                        return null;
                      },
                    ),
                  ),

                  const SizedBox(width: 8),

                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ElevatedButton(
                      onPressed: _generatePin,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 18,
                          horizontal: 16,
                        ),
                        backgroundColor: accentColor,
                      ),
                      child: const Text("Generate"),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Designation
              TextFormField(
                controller: _designationController,
                decoration: const InputDecoration(
                  labelText: "Designation *",
                  prefixIcon: Icon(Icons.work),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Please enter designation";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Department
              TextFormField(
                controller: _departmentController,
                decoration: const InputDecoration(
                  labelText: "Department *",
                  prefixIcon: Icon(Icons.business),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Please enter department";
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Email
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: "Email",
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!emailRegex.hasMatch(value)) {
                      return "Please enter a valid email address";
                    }
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Phone
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Phone Number",
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // Country
              TextFormField(
                controller: _countryController,
                decoration: const InputDecoration(
                  labelText: "Country",
                  prefixIcon: Icon(Icons.flag),
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              // Birthdate with date picker
              TextFormField(
                controller: _birthdateController,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: "Birthdate",
                  prefixIcon: const Icon(Icons.cake),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: _selectDate,
                  ),
                ),
                onTap: _selectDate,
              ),

              const SizedBox(height: 24),

              // Note about face registration
              const Text(
                "Note: After creating an employee, they will need to log in with their PIN and complete the face registration process.",
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),

              const SizedBox(height: 24),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveEmployee,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    _isEditMode ? "Update Employee" : "Add Employee",
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