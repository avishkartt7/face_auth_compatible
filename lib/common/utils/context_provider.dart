// lib/common/utils/context_provider.dart

import 'package:flutter/material.dart';

// This is a better way to manage global context without late initialization errors
class ContextProvider {
  // Use a private static instance to implement the singleton pattern
  static final ContextProvider _instance = ContextProvider._internal();

  // Factory constructor returns the singleton instance
  factory ContextProvider() {
    return _instance;
  }

  // Private constructor for singleton
  ContextProvider._internal();

  // Use nullable BuildContext to avoid late initialization errors
  BuildContext? _context;

  // Setter for the context
  void setContext(BuildContext context) {
    _context = context;
  }

  // Safe getter with fallback
  BuildContext get context {
    if (_context == null) {
      throw FlutterError(
          'Context was accessed before being initialized.\n'
              'Make sure to call ContextProvider().setContext() in your root widget\'s build method.'
      );
    }
    return _context!;
  }

  // Safe way to check if context is available
  bool get hasContext => _context != null;

  // Helper method to get MediaQuery data safely
  Size getScreenSize() {
    if (!hasContext) {
      // Return a default size if context is not available
      return const Size(360, 640); // Common mobile size as fallback
    }
    return MediaQuery.of(context).size;
  }

  // Helper method to get screen width safely
  double get screenWidth => getScreenSize().width;

  // Helper method to get screen height safely
  double get screenHeight => getScreenSize().height;
}