import 'package:flutter/material.dart';

// Queen Builders brand palette and semantic interface colors.
class AppColors {
  AppColors._();

  // Brand colors sampled from the Queen Builders identity.
  static const Color brandBlack = Color(0xFF050505);
  static const Color brandGold = Color(0xFFAC934F);
  static const Color brandGoldLight = Color(0xFFE1C684);
  static const Color brandWhite = Color(0xFFFFFFFF);

  // Theme aliases.
  static const Color primary = brandGold;
  static const Color secondary = brandBlack;
  static const Color accent = brandGoldLight;
  static const Color richGold = brandGold;
  static const Color deepBlack = brandBlack;
  static const Color softWhite = Color(0xFFF8F6F0);
  static const Color textDark = brandBlack;
  static const Color textLight = brandWhite;

  // UI Colors
  static const Color background = softWhite;
  static const Color cardBackground = brandWhite;
  static const Color textPrimary = deepBlack;
  static const Color textSecondary = Color(0xFF686257);
  static const Color border = Color(0xFFDED5C0);
  static const Color disabled = Color(0xFFAAA394);
  static const Color selected = Color(0xFFF1E6C9);

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
