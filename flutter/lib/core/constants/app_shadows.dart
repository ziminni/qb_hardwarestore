import 'package:flutter/material.dart';

// Shared shadow styles for elevated surfaces and cards.

class AppShadows {
  static const BoxShadow card = BoxShadow(
    color: Color(0x14000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  static const BoxShadow elevated = BoxShadow(
    color: Color(0x1F000000),
    blurRadius: 12,
    offset: Offset(0, 4),
  );
}
