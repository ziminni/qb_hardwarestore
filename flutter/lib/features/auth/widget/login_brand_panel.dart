import 'dart:math' as math;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:client/shared/widgets/system_brand.dart';
import 'package:flutter/material.dart';

/// The black half of the wide login screen: the brand on the app's own palette,
/// with no background photograph and no blur.
///
/// [compact] renders the white brand tile alone, for the single-column layout a
/// narrow window uses, where there is no room for the panel.
class LoginBrandPanel extends StatelessWidget {
  const LoginBrandPanel({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandWhite,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      // The logo file is a JPEG on a white square, so it sits on a white tile
      // rather than directly on black.
      child: SystemBrand(
        logoSize: compact ? 32 : 44,
        fontSize: compact ? 14 : 18,
        textColor: AppColors.brandBlack,
        uppercase: true,
      ),
    );

    if (compact) return tile;

    return ColoredBox(
      color: AppColors.chrome,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The design system's blueprint backdrop: a faint grid and one gold
          // hexagon, drawn still rather than animating, so reduced motion is
          // honoured by construction.
          const IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _BrandPainter()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tile,
                const SizedBox(height: AppSpacing.xl),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Text(
                    'Hardware operations, inventory, and sales, '
                    'managed in one reliable workspace.',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The grid, corner marks and hexagon drawn behind the brand copy.
class _BrandPainter extends CustomPainter {
  const _BrandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    Blueprint.paintGrid(canvas, size);
    Blueprint.paintCornerMarks(canvas, size);

    // Off-centre on the right, where the panel's empty space is.
    final radius = math.min(size.width * 0.3, size.height * 0.34);
    final center = Offset(size.width - radius - 56, size.height * 0.42);
    final points = Blueprint.hexagonPoints(center, radius);

    final construction = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    for (final point in points) {
      canvas.drawLine(center, point, construction);
    }

    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius),
      1,
      Paint()
        ..color = AppColors.brandGold.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius * 0.8),
      1,
      Paint()
        ..color = AppColors.brandGold.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _BrandPainter oldDelegate) => false;
}
