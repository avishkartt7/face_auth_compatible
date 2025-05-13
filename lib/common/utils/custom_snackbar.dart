import 'package:face_auth_compatible/constants/theme.dart';
import 'package:flutter/material.dart';

/// CustomSnackBar with backward compatibility support
class CustomSnackBar {
  // Static variable to hold context, nullable for safety
  static BuildContext? context;

  /// Show an error snackbar with the given message
  /// Supports both old API (just message) and new API (context + message)
  static void errorSnackBar([dynamic contextOrMessage, String? message]) {
    // If only one parameter and it's a String, use the old API
    if (message == null && contextOrMessage is String) {
      _showErrorWithStaticContext(contextOrMessage);
      return;
    }

    // If two parameters with first being BuildContext, use the new API
    if (contextOrMessage is BuildContext) {
      _showErrorWithContext(contextOrMessage, message ?? "");
      return;
    }

    // Fallback case - try to use static context
    _showErrorWithStaticContext(contextOrMessage?.toString() ?? "Error occurred");
  }

  /// Show a success snackbar with the given message
  /// Supports both old API (just message) and new API (context + message)
  static void successSnackBar([dynamic contextOrMessage, String? message]) {
    // If only one parameter and it's a String, use the old API
    if (message == null && contextOrMessage is String) {
      _showSuccessWithStaticContext(contextOrMessage);
      return;
    }

    // If two parameters with first being BuildContext, use the new API
    if (contextOrMessage is BuildContext) {
      _showSuccessWithContext(contextOrMessage, message ?? "");
      return;
    }

    // Fallback case - try to use static context
    _showSuccessWithStaticContext(contextOrMessage?.toString() ?? "Success");
  }

  /// Show a warning snackbar with the given message
  static void warningSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.orange,
      ),
    );
  }

  // Private helper methods

  // Show error snackbar using static context
  static void _showErrorWithStaticContext(String message) {
    if (context == null) {
      print("WARNING: CustomSnackBar's static context is null. Cannot show error: $message");
      return;
    }

    try {
      ScaffoldMessenger.of(context!).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context!).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      print("Error showing snackbar: $e");
    }
  }

  // Show error snackbar using passed context
  static void _showErrorWithContext(BuildContext context, String message) {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      print("Error showing snackbar: $e");
    }
  }

  // Show success snackbar using static context
  static void _showSuccessWithStaticContext(String message) {
    if (context == null) {
      print("WARNING: CustomSnackBar's static context is null. Cannot show success: $message");
      return;
    }

    try {
      ScaffoldMessenger.of(context!).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: accentColor,
        ),
      );
    } catch (e) {
      print("Error showing snackbar: $e");
    }
  }

  // Show success snackbar using passed context
  static void _showSuccessWithContext(BuildContext context, String message) {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: accentColor,
        ),
      );
    } catch (e) {
      print("Error showing snackbar: $e");
    }
  }
}