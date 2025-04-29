// lib/pin_entry/app_password_entry_view.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/common/utils/extensions/size_extension.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/dashboard/user_dashboard.dart';
import 'package:flutter/material.dart';

class AppPasswordEntryView extends StatefulWidget {
  const AppPasswordEntryView({Key? key}) : super(key: key);

  @override
  State<AppPasswordEntryView> createState() => _AppPasswordEntryViewState();
}

class _AppPasswordEntryViewState extends State<AppPasswordEntryView> {
  final TextEditingController _passwordController = TextEditingController();
  final List<String> _enteredDigits = ['', '', '', ''];
  int _currentDigitIndex = 0;
  bool _isLoading = false;
  bool _showError = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _addDigit(String digit) {
    if (_currentDigitIndex < 4) {
      setState(() {
        _enteredDigits[_currentDigitIndex] = digit;
        _currentDigitIndex++;
        _showError = false;
      });

      // If all digits entered, verify password
      if (_currentDigitIndex == 4) {
        _verifyPassword();
      }
    }
  }

  void _removeDigit() {
    if (_currentDigitIndex > 0) {
      setState(() {
        _currentDigitIndex--;
        _enteredDigits[_currentDigitIndex] = '';
        _showError = false;
      });
    }
  }

  void _clearEntry() {
    setState(() {
      for (int i = 0; i < 4; i++) {
        _enteredDigits[i] = '';
      }
      _currentDigitIndex = 0;
      _showError = false;
    });
  }

  String get _enteredPassword => _enteredDigits.join();

  Future<void> _verifyPassword() async {
    setState(() => _isLoading = true);

    try {
      // Query Firestore for employee with this app password
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('employees')
          .where('appPassword', isEqualTo: _enteredPassword)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        setState(() {
          _isLoading = false;
          _showError = true;
        });
        return;
      }

      // Get employee data
      final employeeDoc = snapshot.docs.first;
      final String employeeId = employeeDoc.id;
      final Map<String, dynamic> employeeData = employeeDoc.data() as Map<String, dynamic>;

      setState(() => _isLoading = false);

      // Navigate to dashboard
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => UserDashboard(
              employeeId: employeeId,
              employeeData: employeeData,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar("Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialize context
    CustomSnackBar.context = context;

    return Scaffold(
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
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Text(
                "Enter App Password",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 0.028.sh,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 0.03.sh),
              _buildPasswordDisplay(),
              if (_showError)
                Padding(
                  padding: EdgeInsets.only(top: 0.02.sh),
                  child: const Text(
                    "Incorrect password. Please try again.",
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 16,
                    ),
                  ),
                ),
              const Spacer(flex: 1),
              _buildNumpad(),
              const Spacer(flex: 1),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordDisplay() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        4,
            (index) => Container(
          margin: EdgeInsets.symmetric(horizontal: 0.02.sw),
          width: 0.12.sw,
          height: 0.12.sw,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _enteredDigits[index].isNotEmpty
                  ? accentColor
                  : Colors.white.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Center(
            child: _enteredDigits[index].isNotEmpty
                ? Container(
              width: 0.05.sw,
              height: 0.05.sw,
              decoration: const BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNumKey('1'),
            _buildNumKey('2'),
            _buildNumKey('3'),
          ],
        ),
        SizedBox(height: 0.02.sh),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNumKey('4'),
            _buildNumKey('5'),
            _buildNumKey('6'),
          ],
        ),
        SizedBox(height: 0.02.sh),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNumKey('7'),
            _buildNumKey('8'),
            _buildNumKey('9'),
          ],
        ),
        SizedBox(height: 0.02.sh),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildActionKey(Icons.backspace, _removeDigit),
            _buildNumKey('0'),
            _buildActionKey(Icons.refresh, _clearEntry),
          ],
        ),
      ],
    );
  }

  Widget _buildNumKey(String digit) {
    return InkWell(
      onTap: _isLoading ? null : () => _addDigit(digit),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 0.02.sw),
        width: 0.18.sw,
        height: 0.18.sw,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            digit,
            style: TextStyle(
              color: Colors.white,
              fontSize: 0.08.sw,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionKey(IconData icon, VoidCallback onPressed) {
    return InkWell(
      onTap: _isLoading ? null : onPressed,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 0.02.sw),
        width: 0.18.sw,
        height: 0.18.sw,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Icon(
            icon,
            color: Colors.white,
            size: 0.06.sw,
          ),
        ),
      ),
    );
  }
}