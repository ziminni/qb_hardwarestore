import 'dart:math' as math;
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:flutter/material.dart';

// Black "blueprint" panel with a self-drawing gold hexagon that echoes the
// Queen Builders logo.
class LoginBrandPanel extends StatefulWidget {
  const LoginBrandPanel({super.key});

  @override
  State<LoginBrandPanel> createState() => _LoginBrandPanelState();
}

class _LoginBrandPanelState extends State<LoginBrandPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    return ColoredBox(
      color: AppColors.brandBlack,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: _BlueprintPainter(progress)),
          ),
          Padding(
            padding: const EdgeInsets.all(48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const HexLogo(size: 64),
                const Spacer(),
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _controller,
                    curve: const Interval(0.45, 1, curve: Curves.easeOut),
                  ),
                  child: const _BrandCopy(),
                ),
                const SizedBox(height: 40),
                const _Footer(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandCopy extends StatelessWidget {
  const _BrandCopy();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HARDWARE MANAGEMENT SYSTEM',
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.brandGold,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'QUEEN\nBUILDERS',
          style: AppTextStyles.h1.copyWith(
            color: AppColors.brandWhite,
            fontSize: 52,
            height: 1.05,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(width: 56, height: 2, color: AppColors.brandGold),
        const SizedBox(height: AppSpacing.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Text(
            'Built on precision. Inventory, sales, and requisitions '
            'measured out in one workspace.',
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.brandWhite.withValues(alpha: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final style = AppTextStyles.labelSmall.copyWith(
      color: AppColors.brandWhite.withValues(alpha: 0.45),
      letterSpacing: 2,
    );

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (index, label) in const [
          'INVENTORY',
          'POINT OF SALE',
          'REQUISITIONS',
        ].indexed) ...[
          if (index > 0)
            Transform.rotate(
              angle: math.pi / 4,
              child: Container(width: 5, height: 5, color: AppColors.brandGold),
            ),
          Text(label, style: style),
        ],
      ],
    );
  }
}

class _BlueprintPainter extends CustomPainter {
  _BlueprintPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    Blueprint.paintGrid(canvas, size);
    Blueprint.paintCornerMarks(canvas, size);
    _paintHexagon(canvas, size);
  }

  void _paintHexagon(Canvas canvas, Size size) {
    final t = progress.value;
    final radius = math.min(size.width * 0.34, size.height * 0.36);
    final center = Offset(size.width - radius - 72, size.height * 0.42);
    final points = Blueprint.hexagonPoints(center, radius);

    // Construction lines from the center to each vertex.
    final construction = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.12 * t)
      ..strokeWidth = 1;
    for (final point in points) {
      canvas.drawLine(center, point, construction);
    }

    // Outer and inner outlines trace themselves in.
    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius),
      t,
      Paint()
        ..color = AppColors.brandGold.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius * 0.8),
      Curves.easeOut.transform(((t - 0.2) / 0.8).clamp(0, 1)),
      Paint()
        ..color = AppColors.brandGold.withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // Stacked gold slats on the upper-right faces, like the logo.
    final slatProgress = ((t - 0.35) / 0.65).clamp(0.0, 1.0);
    canvas.save();
    canvas.clipPath(Blueprint.hexagonPath(center, radius));
    for (var i = 0; i < 5; i++) {
      final appear = Curves.easeOut.transform(
        ((slatProgress - i * 0.12) / 0.5).clamp(0.0, 1.0),
      );
      if (appear == 0) continue;

      final inset = 0.1 + i * 0.085;
      final slat = Paint()
        ..shader = LinearGradient(
          colors: [
            AppColors.brandGold.withValues(alpha: 0.42 * appear),
            AppColors.brandGoldLight.withValues(alpha: 0.2 * appear),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..strokeWidth = radius * 0.032
        ..strokeCap = StrokeCap.butt;

      for (final (from, to) in [
        (points[0], points[1]),
        (points[1], points[2]),
      ]) {
        final start = Offset.lerp(from, center, inset)!;
        final end = Offset.lerp(to, center, inset)!;
        canvas.drawLine(start, Offset.lerp(start, end, appear)!, slat);
      }
    }
    canvas.restore();

    _paintDimensionLine(canvas, points[0], points[3], points[1].dx + 32, t);
  }

  // Vertical blueprint dimension line spanning the hexagon's height.
  void _paintDimensionLine(
    Canvas canvas,
    Offset top,
    Offset bottom,
    double x,
    double t,
  ) {
    final opacity = ((t - 0.6) / 0.4).clamp(0.0, 1.0);
    if (opacity == 0) return;

    final paint = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.45 * opacity)
      ..strokeWidth = 1;

    final start = Offset(x, top.dy);
    final end = Offset(x, bottom.dy);
    canvas.drawLine(start, end, paint);
    for (final y in [top.dy, bottom.dy]) {
      canvas.drawLine(Offset(x - 6, y), Offset(x + 6, y), paint);
    }

    final label = TextPainter(
      text: TextSpan(
        text: 'QUEEN BUILDERS',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.brandGold.withValues(alpha: 0.6 * opacity),
          fontSize: 9,
          letterSpacing: 2.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(x, (start.dy + end.dy) / 2);
    canvas.rotate(-math.pi / 2);
    final labelOffset = Offset(-label.width / 2, -label.height / 2);
    canvas.drawRect(
      Rect.fromLTWH(
        labelOffset.dx - 8,
        labelOffset.dy,
        label.width + 16,
        label.height,
      ),
      Paint()..color = AppColors.brandBlack,
    );
    label.paint(canvas, labelOffset);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BlueprintPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
