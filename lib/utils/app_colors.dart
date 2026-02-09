import 'package:flutter/material.dart';

class AppColors {
  // Primary green color
  static const Color primaryGreen = Color(0xFF2ECC71);
  static const Color primaryGreenAlt = Color(0xFF36A065);
  
  // Gradient colors for login background (Figma exact colors)
  static const Color gradientTopRight = Color(0xFF1FE07A); // Top-right
  static const Color gradientBottomLeft = Color(0xFF019E6F); // Bottom-left
  static const Color gradientStart = Color(0xFF2E8B57);
  static const Color gradientEnd = Color(0xFF3CB371);
  
  // Login specific colors
  static const Color loginGreen = Color(0xFF1FE07A);
  static const Color inputBg = Color(0xFFF0F0F0);
  
  // Text colors
  static const Color darkGrey = Color(0xFF4A4A4A);
  static const Color darkGreyAlt = Color(0xFF333333);
  static const Color lightGrey = Color(0xFF9B9B9B);
  static const Color mediumGrey = Color(0xFF666666);
  
  // Background colors
  static const Color inputBackground = Color(0xFFEEEEEE);
  static const Color selectedAudienceBg = Color(0xFFD0D0D0); // Darker gray for selected audience chips
  static const Color white = Colors.white;
  static const Color suggestedAudienceBg = Color(0xFFFFF9E6); // Light yellow
  static const Color draftBannerBg = Color(0xFFB8E6B8); // Light mint green
  static const Color dashboardInnerBg = Color(0xFFF4F3F2); // Light beige/gray for dashboard inner panel
  
  // Border colors
  static const Color aiRefinedBorder = Color(0xFFADD8E6); // Light blue
  
  // Action colors
  static const Color deleteRed = Color(0xFFE74C3C);
  static const Color deleteRedAlt = Color(0xFFC0392B);
  static const Color errorBannerBg = Color(0xFFF5D0D0); // Light red for error notifications (draft-style)
  
  // Shadow
  static Color shadowColor = Colors.black.withOpacity(0.1);
}
