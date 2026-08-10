import 'package:flutter/material.dart';

// Centralized color palette used throughout the app.
class AppColors {
  static const primary = Colors.deepPurple;
  static const secondary = Colors.deepPurpleAccent;

  // static const background = Colors.white;
  static const textDark = Colors.black;
  static const textLight = Colors.white;

    // Primary Brand Colors
  static const Color richGold = Color(0xFFC5A46D);
  static const Color deepBlack = Color(0xFF0F0F0F);
  static const Color softWhite = Color(0xFFF5F5F5);

  // UI Colors
  static const Color background = softWhite;
  static const Color cardBackground = Colors.white;
  static const Color textPrimary = deepBlack;
  static const Color textSecondary = Color(0xFF666666);
  static const Color border = Color(0xFFE0E0E0);

  // Status Colors
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color info = Color(0xFF3B82F6);

  // Stock Status Colors
  static const Color stockOk = success;
  static const Color stockLow = warning;
  static const Color stockCritical = error;
}