// lib/pin_entry/user_profile_view.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/common/views/custom_button.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/model/user_model.dart';
import 'package:face_auth_compatible/register_face/register_face_view.dart';
import 'package:flutter/material.dart';

class UserProfileView extends StatefulWidget {
  final String employeePin;
  final UserModel user;
  final bool isNewUser;

  const UserProfileView({
    Key? key,
    required this.employeePin,
    required this.user,
    required this.isNewUser,
  }) : super(key: key);

  @override
  State<UserProfileView> createState() => _UserProfileViewState();
}

class _UserProfileViewState extends State<UserProfileView> {
  late TextEditingController _nameController;
  late TextEditingController _designationController;
  late TextEditingController _departmentController;
  late TextEditingController _birthdateController;
  late TextEditingController _countryController;
  late TextEditingController _emailController;

  // Add break time controllers
  late TextEditingController _breakStartTimeController;
  late TextEditingController _breakEndTimeController;
  late TextEditingController _jummaBreakStartController;
  late TextEditingController _jummaBreakEndController;

  bool _isLoading = false;
  bool _isEditing = false;
  bool _hasJummaBreak = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.name ?? '');
    _designationController = TextEditingController(text: '');
    _departmentController = TextEditingController(text: '');
    _birthdateController = TextEditingController(text: '');
    _countryController = TextEditingController(text: '');
    _emailController = TextEditingController(text: '');

    // Initialize break time controllers
    _breakStartTimeController = TextEditingController(text: '');
    _breakEndTimeController = TextEditingController(text: '');
    _jummaBreakStartController = TextEditingController(text: '');
    _jummaBreakEndController = TextEditingController(text: '');

    // If new user, enable editing by default
    _isEditing = widget.isNewUser;

    // Load existing data if available
    _loadUserData();
  }

  void _loadUserData() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.user.id)
          .get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        setState(() {
          _designationController.text = data['designation'] ?? '';
          _departmentController.text = data['department'] ?? '';
          _birthdateController.text = data['birthdate'] ?? '';
          _countryController.text = data['country'] ?? '';
          _emailController.text = data['email'] ?? '';

          // Load break time data
          _breakStartTimeController.text = data['breakStartTime'] ?? '';
          _breakEndTimeController.text = data['breakEndTime'] ?? '';
          _hasJummaBreak = data['hasJummaBreak'] ?? false;
          _jummaBreakStartController.text = data['jummaBreakStart'] ?? '';
          _jummaBreakEndController.text = data['jummaBreakEnd'] ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error loading profile: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _designationController.dispose();
    _departmentController.dispose();
    _birthdateController.dispose();
    _countryController.dispose();
    _emailController.dispose();
    _breakStartTimeController.dispose();
    _breakEndTimeController.dispose();
    _jummaBreakStartController.dispose();
    _jummaBreakEndController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: appBarColor,
        title: Text(widget.isNewUser ? "Complete Your Profile" : "Your Profile"),
        elevation: 0,
        actions: [
          if (!widget.isNewUser)
            IconButton(
              icon: Icon(_isEditing ? Icons.check : Icons.edit),
              onPressed: () {
                setState(() {
                  if (_isEditing) {
                    _saveProfile();
                  } else {
                    _isEditing = true;
                  }
                });
              },
            ),
        ],
      ),
      body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scaffoldTopGradientClr,
                scaffoldBottomGradientClr,
              ],
            ),
          ),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: accentColor))
              : SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 100, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Center(
            child: CircleAvatar(
            radius: 60,
              backgroundColor: primaryWhite.withOpacity(0.2),
              child: const Icon(
                Icons.person,
                size: 80,
                color: primaryWhite,
              ),
            ),
          ),
          const SizedBox(height: 32),
          _buildProfileField(
            label: "Name",
            controller: _nameController,
            enabled: _isEditing,
          ),
          _buildProfileField(
            label: "Designation",
            controller: _designationController,
            enabled: _isEditing,
          ),
          _buildProfileField(
            label: "Department",
            controller: _departmentController,
            enabled: _isEditing,
          ),
          _buildProfileField(
            label: "Birthdate",
            controller: _birthdateController,
            enabled: _isEditing,
            hint: "DD/MM/YYYY",
          ),
          _buildProfileField(
            label: "Country",
            controller: _countryController,
            enabled: _isEditing,
          ),
          _buildProfileField(
            label: "Email (Optional)",
            controller: _emailController,
            enabled: _isEditing,
            hint: "your.email@example.com",
          ),

          const SizedBox(height: 24),

          // Break Time Section
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                const Text(
                "Break Time Settings",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // Daily break time
              Row(
                children: [
                  Expanded(
                    child: _buildTimeField(
                      label: "Break Start Time",
                      controller: _breakStartTimeController,
                      enabled: _isEditing,
                      isRequired: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTimeField(
                      label: "Break End Time",
                      controller: _breakEndTimeController,
                      enabled: _isEditing,
                      isRequired: true,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Jumma break toggle
              SwitchListTile(
                title: const Text(
                  "Friday Prayer Break",
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  "Enable if you take Friday prayer break",
                  style: TextStyle(color: Colors.white70),
                ),
                value: _hasJummaBreak,
                onChanged: _isEditing ? (value) {
                  setState(() {
                    _hasJummaBreak = value;
                    if (!value) {
                      _jummaBreakStartController.clear();
                      _jummaBreakEndController.clear();
                    }
                  });
                } : null,
                activeColor: accentColor,
              ),

              // Jumma break time (only visible if enabled)
              if (_hasJummaBreak) ...[
          const SizedBox(height: 16),
      Row(
        children: [
      Expanded(
      child: _buildTimeField(
      label: "Jumma Start",
        controller: _jummaBreakStartController,
        enabled: _isEditing,
        isRequired: true,
      ),
    ),
    const SizedBox(width: 16),
          Expanded(
            child: _buildTimeField(
              label: "Jumma End",
              controller: _jummaBreakEndController,
              enabled: _isEditing,
              isRequired: true,
            ),
          ),
        ],
      ),
              ],
                ],
              ),
          ),

                const SizedBox(height: 32),

                if (widget.isNewUser || _isEditing)
                  Center(
                    child: CustomButton(
                      text: widget.isNewUser ? "Confirm & Continue" : "Save Changes",
                      onTap: _saveProfile,
                    ),
                  ),
              ],
            ),
          ),
      ),
    );
  }

  Widget _buildProfileField({
    required String label,
    required TextEditingController controller,
    bool enabled = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: primaryWhite.withOpacity(0.8),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            enabled: enabled,
            style: const TextStyle(
              color: primaryWhite,
              fontSize: 18,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: primaryWhite.withOpacity(0.4),
                fontSize: 16,
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: primaryWhite.withOpacity(0.1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeField({
    required String label,
    required TextEditingController controller,
    bool enabled = false,
    bool isRequired = false,
  }) {
    return GestureDetector(
      onTap: enabled ? () => _selectTime(controller) : null,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.1),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Row(
          children: [
            Icon(
              Icons.access_time,
              color: Colors.white.withOpacity(0.8),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$label${isRequired ? ' *' : ''}",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    controller.text.isNotEmpty ? controller.text : "Tap to select",
                    style: TextStyle(
                      color: controller.text.isNotEmpty
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveProfile() async {
    // Validate fields
    if (_nameController.text.trim().isEmpty ||
        _designationController.text.trim().isEmpty ||
        _departmentController.text.trim().isEmpty ||
        _breakStartTimeController.text.trim().isEmpty ||
        _breakEndTimeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill in all required fields"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate Jumma break times if enabled
    if (_hasJummaBreak &&
        (_jummaBreakStartController.text.trim().isEmpty ||
            _jummaBreakEndController.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill in Jumma break times"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Update user profile in Firestore
      await FirebaseFirestore.instance
          .collection('employees')
          .doc(widget.user.id)
          .update({
        'name': _nameController.text.trim(),
        'designation': _designationController.text.trim(),
        'department': _departmentController.text.trim(),
        'birthdate': _birthdateController.text.trim(),
        'country': _countryController.text.trim(),
        'email': _emailController.text.trim(),
        'breakStartTime': _breakStartTimeController.text.trim(),
        'breakEndTime': _breakEndTimeController.text.trim(),
        'hasJummaBreak': _hasJummaBreak,
        'jummaBreakStart': _jummaBreakStartController.text.trim(),
        'jummaBreakEnd': _jummaBreakEndController.text.trim(),
        'profileCompleted': true,
      });

      setState(() => _isLoading = false);

      if (widget.isNewUser) {
        // If new user, proceed to face registration
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RegisterFaceView(
                employeeId: widget.user.id!,
                employeePin: widget.employeePin,
              ),
            ),
          );
        }
      } else {
        // If existing user, just exit edit mode
        setState(() => _isEditing = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Profile updated successfully"),
              backgroundColor: accentColor,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving profile: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}