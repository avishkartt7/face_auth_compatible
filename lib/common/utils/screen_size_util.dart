// lib/common/utils/screen_size_util.dart

import 'package:flutter/material.dart';

class ScreenSizeUtil {
  // Use static nullable variable instead of late to avoid initialization errors
  static BuildContext? _context;

  // Setter method for context
  static set context(BuildContext ctx) {
    _context = ctx;
  }

  // Getter with safety check
  static BuildContext get context {
    if (_context == null) {
      throw FlutterError(
          'ScreenSizeUtil._context has not been initialized.\n'
              'Make sure to call ScreenSizeUtil.context = context in your build method.'
      );
    }
    return _context!;
  }

  // Use safe access with fallback values
  static double get screenWidth {
    if (_context == null) {
      return 360.0; // Default mobile width
    }
    return MediaQuery.of(_context!).size.width;
  }

  static double get screenHeight {
    if (_context == null) {
      return 640.0; // Default mobile height
    }
    return MediaQuery.of(_context!).size.height;
  }
}