import 'dart:math' as math;

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:flutter/material.dart';

/// The dark-chrome brand showcase of the login screen: architectural blueprint
/// geometry on Queen Builders' obsidian and gold palette, with no background
/// photograph and no blur filter.
///
/// [compact] renders a refined obsidian brand banner for narrow desktop
/// windows, tablets, and mobile screens where the split layout collapses into
/// a single column.
class LoginBrandPanel extends StatelessWidget {
  const LoginBrandPanel({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (compact) return const _CompactBrandBanner();

    return ColoredBox(
      color: AppColors.chrome,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Static architectural drafting backdrop — no repeating animation so
          // reduced-motion preferences and deterministic tests stay honoured.
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _BrandPainter(
                  accent: p.accent,
                  accentLight: p.accentLight,
                ),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth >= 640
                  ? 52.0
                  : 36.0;
              final compactHeight = constraints.maxHeight < 720;

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: compactHeight ? 28 : 40,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: math.max(
                      0,
                      constraints.maxHeight - (compactHeight ? 56 : 80),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _TopEyebrow(),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: compactHeight ? 24 : 36,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _BrandLockup(),
                            SizedBox(height: compactHeight ? 24 : 32),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: Text(
                                'Built for the counter,\nstockroom & bodega.',
                                style: AppTextStyles.h1.copyWith(
                                  fontSize: constraints.maxWidth >= 600
                                      ? 32
                                      : 27,
                                  height: 1.24,
                                  color: AppColors.brandWhite,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Container(
                              width: 52,
                              height: 2.5,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(2),
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.brandGold,
                                    AppColors.brandGoldLight,
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Text(
                                'Hardware operations, inventory, and sales '
                                'managed in one reliable workspace.',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.chromeText,
                                  fontSize: 14.5,
                                  height: 1.55,
                                ),
                              ),
                            ),
                            SizedBox(height: compactHeight ? 24 : 34),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: const _WorkspacePillars(),
                            ),
                          ],
                        ),
                      ),
                      const _BottomFooter(),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TopEyebrow extends StatelessWidget {
  const _TopEyebrow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 2,
          color: AppColors.brandGold,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'BUILDPRO OPERATIONS SUITE',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.brandGoldLight,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppColors.chromeRaised.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: AppColors.chromeBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.brandWhite,
              borderRadius: BorderRadius.circular(AppRadii.small + 2),
              border: Border.all(
                color: AppColors.brandGold.withValues(alpha: 0.45),
              ),
            ),
            child: Image.asset(
              AppAssets.logo,
              fit: BoxFit.contain,
              semanticLabel: 'Queen Builders logo',
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QUEEN BUILDERS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h3.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandWhite,
                    letterSpacing: 1.1,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'HARDWARE & CONSTRUCTION SUPPLY',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.brandGoldLight,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.35,
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

class _WorkspacePillars extends StatelessWidget {
  const _WorkspacePillars();

  static const _items = [
    (
      icon: Icons.point_of_sale_rounded,
      title: 'Front Counter & Till',
      subtitle: 'Sales, receipts, shifts, and customer receivables',
    ),
    (
      icon: Icons.inventory_2_outlined,
      title: 'Inventory & Purchasing',
      subtitle: 'FIFO stock batches, suppliers, and branch transfers',
    ),
    (
      icon: Icons.warehouse_outlined,
      title: 'Bodega & Releases',
      subtitle: 'Receipt-QR pick-ups and supplier delivery checks',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.chromeRaised.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: AppColors.chromeBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: AppColors.chromeBorder,
              ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 13,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.brandGold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadii.small),
                      border: Border.all(
                        color: AppColors.brandGold.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Icon(
                      _items[i].icon,
                      size: 18,
                      color: AppColors.brandGoldLight,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _items[i].title,
                          style: AppTextStyles.labelLarge.copyWith(
                            color: AppColors.brandWhite,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _items[i].subtitle,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.chromeText,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BottomFooter extends StatelessWidget {
  const _BottomFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1, thickness: 1, color: AppColors.chromeBorder),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.xs,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.brandGold,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Queen Builders POS & Inventory',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.chromeText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            Text(
              'INTERNAL WORKSPACE',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.brandGold,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Narrow-screen obsidian brand banner that carries the same architectural
/// identity into single-column tablet and Android layouts.
class _CompactBrandBanner extends StatelessWidget {
  const _CompactBrandBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.chrome,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlack.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: AppColors.chromeBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _CompactBrandPainter()),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.brandWhite,
                        borderRadius: BorderRadius.circular(AppRadii.small),
                        border: Border.all(
                          color: AppColors.brandGold.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Image.asset(
                        AppAssets.logo,
                        fit: BoxFit.contain,
                        semanticLabel: 'Queen Builders logo',
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'QUEEN BUILDERS',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.h4.copyWith(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandWhite,
                              letterSpacing: 1.0,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'BUILDPRO POS & INVENTORY',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.brandGoldLight,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 3,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.brandGold,
                      AppColors.brandGoldLight,
                      AppColors.brandGold,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Architectural blueprint grid, radial brass glow, drafting axes, and
/// nested accent hexagons drawn behind the wide brand panel.
class _BrandPainter extends CustomPainter {
  const _BrandPainter({required this.accent, required this.accentLight});

  final Color accent;
  final Color accentLight;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width * 0.29, size.height * 0.27);
    final center = Offset(size.width * 0.84, size.height * 0.25);

    // Subtle warm spotlight behind the geometric emblem.
    final glowRect = Rect.fromCircle(center: center, radius: radius * 1.9);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: 0.14),
          accent.withValues(alpha: 0.04),
          Colors.transparent,
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(glowRect);
    canvas.drawRect(Offset.zero & size, glowPaint);

    Blueprint.paintGrid(canvas, size, opacity: 0.85, color: accent);
    Blueprint.paintCornerMarks(canvas, size, opacity: 0.7, color: accent);

    // Drafting axis crosshairs through the hexagon center.
    final axisPaint = Paint()
      ..color = accent.withValues(alpha: 0.1)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      axisPaint,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      axisPaint,
    );

    final points = Blueprint.hexagonPoints(center, radius);
    final spokePaint = Paint()
      ..color = accent.withValues(alpha: 0.11)
      ..strokeWidth = 1;
    for (final point in points) {
      canvas.drawLine(center, point, spokePaint);
    }

    // Outer, middle, and core architectural hexagons.
    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius),
      1,
      Paint()
        ..color = accent.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius * 0.78),
      1,
      Paint()
        ..color = accent.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius * 0.52),
      1,
      Paint()
        ..color = accentLight.withValues(alpha: 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Crisp vertex registration dots on the outer hexagon.
    final nodePaint = Paint()
      ..color = accentLight.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    for (final point in points) {
      canvas.drawCircle(point, 2.5, nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _BrandPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.accentLight != accentLight;
}

class _CompactBrandPainter extends CustomPainter {
  const _CompactBrandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    Blueprint.paintGrid(canvas, size, opacity: 0.65);

    final center = Offset(size.width - 28, size.height * 0.5);
    final radius = size.height * 0.62;
    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius),
      1,
      Paint()
        ..color = AppColors.brandGold.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius * 0.68),
      1,
      Paint()
        ..color = AppColors.brandGold.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _CompactBrandPainter oldDelegate) => false;
}
