// lib/common/views/custom_button.dart

import 'package:face_auth_compatible/constants/theme.dart';
import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const CustomButton({
    Key? key,
    required this.text,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Get dimensions directly from MediaQuery
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Calculate values based on screen size
    final double horizontalMargin = screenWidth * 0.05;
    final double paddingAll = screenWidth * 0.03;
    final double leftPadding = screenWidth * 0.03;
    final double fontSize = screenHeight * 0.025;
    final double borderRadius = screenHeight * 0.02;
    final double avatarRadius = screenHeight * 0.03;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
        decoration: BoxDecoration(
          color: buttonColor,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
        child: Padding(
          padding: EdgeInsets.all(paddingAll),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: EdgeInsets.only(left: leftPadding),
                child: Text(
                  text,
                  style: TextStyle(
                    color: primaryBlack,
                    fontSize: fontSize,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              CircleAvatar(
                radius: avatarRadius,
                backgroundColor: accentColor,
                child: const Icon(
                  Icons.arrow_circle_right,
                  color: buttonColor,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}