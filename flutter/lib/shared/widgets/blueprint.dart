import 'dart:math' as math;
import 'dart:ui';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

// Shared "blueprint" drawing helpers for the splash and login brand screens.
class Blueprint {
  Blueprint._();

  static const double minorStep = 28;
  static const double majorStep = minorStep * 5;

  // Pointy-top hexagon vertices, clockwise from the top.
  static List<Offset> hexagonPoints(Offset center, double radius) {
    return [
      for (var i = 0; i < 6; i++)
        center + Offset.fromDirection((-90 + 60 * i) * math.pi / 180, radius),
    ];
  }

  static Path hexagonPath(Offset center, double radius) {
    return Path()..addPolygon(hexagonPoints(center, radius), true);
  }

  static void paintGrid(Canvas canvas, Size size, {double opacity = 1}) {
    final minor = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.05 * opacity)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.11 * opacity)
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += minorStep) {
      final paint = x % majorStep == 0 ? major : minor;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += minorStep) {
      final paint = y % majorStep == 0 ? major : minor;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  static void paintCornerMarks(Canvas canvas, Size size, {double opacity = 1}) {
    const inset = 20.0;
    const length = 18.0;
    final paint = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.5 * opacity)
      ..strokeWidth = 1.2;

    final corners = [
      (Offset(inset, inset), const Offset(1, 1)),
      (Offset(size.width - inset, inset), const Offset(-1, 1)),
      (Offset(inset, size.height - inset), const Offset(1, -1)),
      (Offset(size.width - inset, size.height - inset), const Offset(-1, -1)),
    ];
    for (final (point, direction) in corners) {
      canvas.drawLine(point, point + Offset(length * direction.dx, 0), paint);
      canvas.drawLine(point, point + Offset(0, length * direction.dy), paint);
    }
  }

  // Draws the first [t] fraction (0-1) of [path].
  static void drawPartialPath(Canvas canvas, Path path, double t, Paint paint) {
    if (t <= 0) return;
    for (final PathMetric metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * t), paint);
    }
  }
}

// Queen Builders logo inside a white hexagon badge.
class HexLogo extends StatelessWidget {
  const HexLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const HexagonClipper(),
      child: Container(
        width: size,
        height: size,
        color: AppColors.brandWhite,
        padding: EdgeInsets.all(size * 0.16),
        child: Image.asset(
          AppAssets.logo,
          fit: BoxFit.contain,
          semanticLabel: 'Queen Builders logo',
        ),
      ),
    );
  }
}

// Clips a child to a pointy-top hexagon.
class HexagonClipper extends CustomClipper<Path> {
  const HexagonClipper();

  @override
  Path getClip(Size size) {
    return Blueprint.hexagonPath(
      size.center(Offset.zero),
      size.shortestSide / 2,
    );
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
