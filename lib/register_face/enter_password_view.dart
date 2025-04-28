import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/common/utils/custom_text_field.dart';
import 'package:face_auth_compatible/common/views/custom_button.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/register_face/user_management_view.dart'; // New import
import 'package:flutter/material.dart';

class EnterPasswordView extends StatelessWidget {
  EnterPasswordView({Key? key}) : super(key: key);

  final TextEditingController _controller = TextEditingController();
  final _formFieldKey = GlobalKey<FormFieldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: appBarColor,
        title: const Text("Enter Password"),
        elevation: 0,
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
        child: Center(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomTextField(
                  formFieldKey: _formFieldKey,
                  controller: _controller,
                  hintText: "Password",
                  validatorText: "Enter password to proceed",
                ),
                CustomButton(
                  text: "Continue",
                  onTap: () async {
                    if (_formFieldKey.currentState!.validate()) {
                      FocusScope.of(context).unfocus();

                      // Show loading indicator
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(color: accentColor),
                        ),
                      );

                      try {
                        final snap = await FirebaseFirestore.instance
                            .collection("password")
                            .doc("PG0eZfMW5FfkOy5JCXuS")
                            .get();

                        // Close loading dialog
                        Navigator.of(context).pop();

                        if (snap.exists && snap.data() != null) {
                          String? storedPassword = snap.data()!['password'];
                          if (storedPassword == _controller.text.trim()) {
                            // Navigate to User Management instead of RegisterFaceView
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const UserManagementView(),
                              ),
                            );
                          } else {
                            CustomSnackBar.errorSnackBar("Wrong Password :( ");
                          }
                        } else {
                          CustomSnackBar.errorSnackBar("Password document not found!");
                        }
                      } catch (e) {
                        // Close loading dialog if it's showing
                        Navigator.of(context, rootNavigator: true).pop();
                        CustomSnackBar.errorSnackBar("Error: ${e.toString()}");
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}