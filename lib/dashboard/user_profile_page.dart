// lib/dashboard/user_profile_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/common/views/custom_button.dart';

class UserProfilePage extends StatefulWidget {
  final String employeeId;
  final Map<String, dynamic> userData;

  const UserProfilePage({
    Key? key,
    required this.employeeId,
    required this.userData,
  }) : super(key: key);

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  late TextEditingController _nameController;
  late TextEditingController _designationController;
  late TextEditingController _departmentController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _countryController;
  late TextEditingController _birthdateController;

  // Add break time controllers
  late TextEditingController _breakStartTimeController;
  late TextEditingController _breakEndTimeController;
  late TextEditingController _jummaBreakStartController;
  late TextEditingController _jummaBreakEndController;

  bool _isEditing = false;
  bool _isLoading = false;
  bool _hasJummaBreak = false;

  @override
  void initState() {
    super.initState();

    // Initialize controllers with user data
    _nameController = TextEditingController(text: widget.userData['name'] ?? '');
    _designationController = TextEditingController(text: widget.userData['designation'] ?? '');
    _departmentController = TextEditingController(text: widget.userData['department'] ?? '');
    _phoneController = TextEditingController(text: widget.userData['phone'] ?? '');
    _emailController = TextEditingController(text: widget.userData['email'] ?? '');
    _countryController = TextEditingController(text: widget.userData['country'] ?? '');
    _birthdateController = TextEditingController(text: widget.userData['birthdate'] ?? '');

    // Initialize break time controllers
    _breakStartTimeController = TextEditingController(text: widget.userData['breakStartTime'] ?? '');
    _breakEndTimeController = TextEditingController(text: widget.userData['breakEndTime'] ?? '');
    _hasJummaBreak = widget.userData['hasJummaBreak'] ?? false;
    _jummaBreakStartController = TextEditingController(text: widget.userData['jummaBreakStart'] ?? '');
    _jummaBreakEndController = TextEditingController(text: widget.userData['jummaBreakEnd'] ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _designationController.dispose();
    _departmentController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _countryController.dispose();
    _birthdateController.dispose();
    _breakStartTimeController.dispose();
    _breakEndTimeController.dispose();
    _jummaBreakStartController.dispose();
    _jummaBreakEndController.dispose();
    super.dispose();
  }

  void _toggleEditing() {
    setState(() {
      _isEditing = !_isEditing;
    });
  }

  Future<void> _selectTime(TextEditingController controller) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
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
        controller.text = picked.format(context);
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_nameController.text.trim().isEmpty) {
      CustomSnackBar.errorSnackBar(context, "Name cannot be empty");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.employeeId)
          .update({
        'name': _nameController.text.trim(),
        'designation': _designationController.text.trim(),
        'department': _departmentController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'country': _countryController.text.trim(),
        'birthdate': _birthdateController.text.trim(),
        'breakStartTime': _breakStartTimeController.text.trim(),
        'breakEndTime': _breakEndTimeController.text.trim(),
        'hasJummaBreak': _hasJummaBreak,
        'jummaBreakStart': _jummaBreakStartController.text.trim(),
        'jummaBreakEnd': _jummaBreakEndController.text.trim(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Update successful
      setState(() {
        _isLoading = false;
        _isEditing = false;
      });

      if (mounted) {
        CustomSnackBar.successSnackBar(context, "Profile updated successfully");
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        CustomSnackBar.errorSnackBar(context, "Error updating profile: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: scaffoldTopGradientClr,
        elevation: 0,
        title: Text(
          _isEditing ? "Edit Profile" : "Profile",
          style: const TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (_isEditing) {
              // Show confirmation dialog if editing
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Discard Changes?"),
                  content: const Text("Any unsaved changes will be lost."),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("Cancel"),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        setState(() {
                          _isEditing = false;
                        });
                        Navigator.of(context).pop();
                      },
                      child: const Text("Discard"),
                    ),
                  ],
                ),
              );
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed: _toggleEditing,
            ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.save, color: Colors.white),
              onPressed: _saveProfile,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: accentColor))
          : SingleChildScrollView(
        child: Column(
          children: [
            // Profile header with image
            _buildProfileHeader(),

            // Profile details
            Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),

                  // Contact information section
                  const Text(
                    "Contact Information",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phone
                  _buildInfoField(
                    label: "Phone",
                    controller: _phoneController,
                    icon: Icons.phone,
                    isEditing: _isEditing,
                    keyboardType: TextInputType.phone,
                  ),

                  // Email
                  _buildInfoField(
                    label: "Email",
                    controller: _emailController,
                    icon: Icons.email,
                    isEditing: _isEditing,
                    keyboardType: TextInputType.emailAddress,
                  ),

                  const SizedBox(height: 32),

                  // Work information section
                  const Text(
                    "Work Information",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Department
                  _buildInfoField(
                    label: "Department",
                    controller: _departmentController,
                    icon: Icons.business,
                    isEditing: _isEditing,
                  ),

                  // Designation
                  _buildInfoField(
                    label: "Designation",
                    controller: _designationController,
                    icon: Icons.work,
                    isEditing: _isEditing,
                  ),

                  const SizedBox(height: 32),

                  // Break Time Information section
                  const Text(
                    "Break Time Information",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Daily break time
                  _buildTimeField(
                    label: "Daily Break Time",
                    startController: _breakStartTimeController,
                    endController: _breakEndTimeController,
                    icon: Icons.coffee,
                    isEditing: _isEditing,
                  ),

                  const SizedBox(height: 16),

                  // Jumma break section
                  if (!_isEditing && _hasJummaBreak) ...[
                    _buildTimeField(
                      label: "Friday Prayer Break (Jumma)",
                      startController: _jummaBreakStartController,
                      endController: _jummaBreakEndController,
                      icon: Icons.mosque,
                      isEditing: false,
                    ),
                  ],

                  if (_isEditing) ...[
                    SwitchListTile(
                      title: const Text("Friday Prayer Break"),
                      subtitle: const Text("Enable if you take Friday prayer break"),
                      value: _hasJummaBreak,
                      onChanged: (value) {
                        setState(() {
                          _hasJummaBreak = value;
                          if (!value) {
                            _jummaBreakStartController.clear();
                            _jummaBreakEndController.clear();
                          }
                        });
                      },
                      activeColor: accentColor,
                    ),

                    if (_hasJummaBreak) ...[
                      const SizedBox(height: 16),
                      _buildTimeField(
                        label: "Friday Prayer Break Time",
                        startController: _jummaBreakStartController,
                        endController: _jummaBreakEndController,
                        icon: Icons.mosque,
                        isEditing: true,
                      ),
                    ],
                  ],

                  const SizedBox(height: 32),

                  // Personal information section
                  const Text(
                    "Personal Information",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Birthdate
                  _buildInfoField(
                    label: "Birthdate",
                    controller: _birthdateController,
                    icon: Icons.cake,
                    isEditing: _isEditing,
                  ),

                  // Country
                  _buildInfoField(
                    label: "Country",
                    controller: _countryController,
                    icon: Icons.location_on,
                    isEditing: _isEditing,
                  ),

                  const SizedBox(height: 40),

                  // Save button when editing
                  if (_isEditing)
                    CustomButton(
                      text: "Save Changes",
                      onTap: _saveProfile,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    String? imageBase64 = widget.userData['image'];

    return Container(
      height: 220,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scaffoldTopGradientClr,
            scaffoldBottomGradientClr,
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Profile image
          Hero(
            tag: 'profile-${widget.employeeId}',
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.white.withOpacity(0.3),
                  child: imageBase64 != null
                      ? ClipOval(
                    child: Image.memory(
                      base64Decode(imageBase64),
                      fit: BoxFit.cover,
                      width: 120,
                      height: 120,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.white,
                        );
                      },
                    ),
                  )
                      : const Icon(
                    Icons.person,
                    size: 60,
                    color: Colors.white,
                  ),
                ),
                if (_isEditing)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.photo_camera,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Name
          _isEditing
              ? Container(
            width: 200,
            child: TextField(
              controller: _nameController,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: "Enter your name",
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                ),
                border: InputBorder.none,
              ),
            ),
          )
              : Text(
            _nameController.text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isEditing,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          isEditing
              ? Row(
            children: [
              Icon(icon, color: Colors.black54, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  decoration: const InputDecoration(
                    border: UnderlineInputBorder(),
                    contentPadding: EdgeInsets.only(bottom: 8),
                  ),
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          )
              : Row(
            children: [
              Icon(icon, color: Colors.black54, size: 22),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  controller.text.isNotEmpty ? controller.text : "Not provided",
                  style: TextStyle(
                    fontSize: 16,
                    color: controller.text.isNotEmpty
                        ? Colors.black87
                        : Colors.black38,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeField({
    required String label,
    required TextEditingController startController,
    required TextEditingController endController,
    required IconData icon,
    required bool isEditing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(icon, color: Colors.black54, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  // Start time
                  Expanded(
                    child: isEditing
                        ? GestureDetector(
                      onTap: () => _selectTime(startController),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey)),
                        ),
                        child: Text(
                          startController.text.isNotEmpty
                              ? startController.text
                              : "Start time",
                          style: TextStyle(
                            fontSize: 16,
                            color: startController.text.isNotEmpty
                                ? Colors.black87
                                : Colors.black38,
                          ),
                        ),
                      ),
                    )
                        : Text(
                      startController.text.isNotEmpty
                          ? startController.text
                          : "Not set",
                      style: TextStyle(
                        fontSize: 16,
                        color: startController.text.isNotEmpty
                            ? Colors.black87
                            : Colors.black38,
                      ),
                    ),
                  ),

                  const SizedBox(width: 16),
                  const Text(" - ", style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 16),

                  // End time
                  Expanded(
                    child: isEditing
                        ? GestureDetector(
                      onTap: () => _selectTime(endController),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey)),
                        ),
                        child: Text(
                          endController.text.isNotEmpty
                              ? endController.text
                              : "End time",
                          style: TextStyle(
                            fontSize: 16,
                            color: endController.text.isNotEmpty
                                ? Colors.black87
                                : Colors.black38,
                          ),
                        ),
                      ),
                    )
                        : Text(
                      endController.text.isNotEmpty
                          ? endController.text
                          : "Not set",
                      style: TextStyle(
                        fontSize: 16,
                        color: endController.text.isNotEmpty
                            ? Colors.black87
                            : Colors.black38,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}