import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:client/shared/widgets/measure_ruler.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// Branded intro shown while the saved session is restored.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final auth = context.read<AuthViewmodel>();
    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (reduceMotion) _controller.value = 1;

    await Future.wait([auth.initialize(), _controller.forward()]);
    if (!mounted) return;

    setState(() => _isReady = true);
    await Future.delayed(const Duration(milliseconds: 250));
    // The router redirects signed-in users to their dashboard.
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _interval(double begin, double end, [Curve? curve]) {
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(begin, end, curve: curve ?? Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logo = _interval(0.3, 0.6, Curves.easeOutBack);
    final title = _interval(0.5, 0.8);
    final subtitle = _interval(0.62, 0.9);

    return Scaffold(
      backgroundColor: AppColors.brandBlack,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: _BackdropPainter(_interval(0, 0.4))),
          ),
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 240,
                    child: CustomPaint(
                      painter: _HexagonPainter(
                        _interval(0, 0.55, Curves.easeInOutCubic),
                      ),
                      child: Center(
                        child: FadeTransition(
                          opacity: logo,
                          child: ScaleTransition(
                            scale: Tween(begin: 0.6, end: 1.0).animate(logo),
                            child: const HexLogo(size: 104),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  AnimatedBuilder(
                    animation: title,
                    builder: (context, child) {
                      return Opacity(
                        opacity: title.value,
                        child: Text(
                          'QUEEN BUILDERS',
                          style: AppTextStyles.h1.copyWith(
                            color: AppColors.brandWhite,
                            fontSize: 30,
                            letterSpacing: 6 + 10 * (1 - title.value),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FadeTransition(
                    opacity: subtitle,
                    child: Text(
                      'HARDWARE MANAGEMENT SYSTEM',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.brandGold,
                        letterSpacing: 3.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  SizedBox(
                    width: 240,
                    height: 14,
                    child: CustomPaint(
                      painter: MeasureProgressPainter(
                        _interval(0.15, 1, Curves.easeInOut),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FadeTransition(
                    opacity: subtitle,
                    child: Text(
                      _isReady ? 'Ready' : 'Preparing workspace...',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.brandWhite.withValues(alpha: 0.5),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    Blueprint.paintGrid(canvas, size, opacity: progress.value);
    Blueprint.paintCornerMarks(canvas, size, opacity: progress.value);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _HexagonPainter extends CustomPainter {
  _HexagonPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final construction = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.14 * t)
      ..strokeWidth = 1;
    for (final point in Blueprint.hexagonPoints(center, radius)) {
      canvas.drawLine(center, point, construction);
    }

    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius),
      t,
      Paint()
        ..color = AppColors.brandGold.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius * 0.82),
      ((t - 0.25) / 0.75).clamp(0.0, 1.0),
      Paint()
        ..color = AppColors.brandGold.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _HexagonPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
