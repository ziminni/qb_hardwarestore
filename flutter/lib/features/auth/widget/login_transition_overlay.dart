import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:client/shared/widgets/measure_ruler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

// Plays a branded hand-off above the router whenever a user signs in: a
// black hexagon closes over the login page, a welcome card names the module,
// then a hexagonal iris opens onto the module's dashboard.
class LoginTransitionOverlay extends StatefulWidget {
  const LoginTransitionOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<LoginTransitionOverlay> createState() => _LoginTransitionOverlayState();
}

class _LoginTransitionOverlayState extends State<LoginTransitionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  late final AuthViewmodel _auth = context.read<AuthViewmodel>();
  final _contentKey = GlobalKey();

  bool _wasSignedIn = false;
  bool _wasInitializing = true;
  _ModuleInfo? _module;
  String _userName = '';

  // The login screen as it looked when sign-in succeeded. The router swaps
  // to the dashboard straight away, so the closing hexagon covers this image.
  ui.Image? _snapshot;

  @override
  void initState() {
    super.initState();
    _wasSignedIn = _auth.isAuthenticated;
    _wasInitializing = _auth.isInitializing;
    _auth.addListener(_handleAuthChanged);
  }

  @override
  void dispose() {
    _auth.removeListener(_handleAuthChanged);
    _controller.dispose();
    _snapshot?.dispose();
    super.dispose();
  }

  void _handleAuthChanged() {
    final signedIn = _auth.isAuthenticated;
    // Only a fresh sign-in plays the transition; a restored session at
    // startup goes straight through the splash screen.
    final freshSignIn = signedIn && !_wasSignedIn && !_wasInitializing;
    _wasSignedIn = signedIn;
    _wasInitializing = _auth.isInitializing;
    if (!freshSignIn) return;

    final reduceMotion = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (reduceMotion) return;

    _snapshot?.dispose();
    _snapshot = _captureScreen();
    setState(() {
      _module = _ModuleInfo.forRole(_auth.roleName);
      _userName = _auth.user?.fullName ?? '';
    });
    _controller.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      _snapshot?.dispose();
      _snapshot = null;
      setState(() => _module = null);
    });
  }

  ui.Image? _captureScreen() {
    try {
      final boundary =
          _contentKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      return boundary.toImageSync(
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    } catch (_) {
      // Without a snapshot the hexagon simply closes over the new page.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final module = _module;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(key: _contentKey, child: widget.child),
        if (module != null)
          Positioned.fill(
            child: AbsorbPointer(
              // Above the navigator there is no Material for text to inherit.
              child: Material(
                type: MaterialType.transparency,
                child: _TransitionLayer(
                  animation: _controller,
                  module: module,
                  userName: _userName,
                  snapshot: _snapshot,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ModuleInfo {
  const _ModuleInfo(this.name, this.icon);

  final String name;
  final IconData icon;

  // Mirrors the role-to-dashboard mapping in the router.
  static _ModuleInfo forRole(String? role) {
    return switch (role) {
      'admin' => const _ModuleInfo(
        'Administration',
        Icons.admin_panel_settings_outlined,
      ),
      'inventory' => const _ModuleInfo('Inventory', Icons.inventory_2_outlined),
      'pos' => const _ModuleInfo('Point of Sale', Icons.point_of_sale_outlined),
      'sales' => const _ModuleInfo('Sales', Icons.storefront_outlined),
      _ => const _ModuleInfo('Workspace', Icons.dashboard_outlined),
    };
  }
}

// Phase boundaries as fractions of the controller.
const double _closeEnd = 0.24;
const double _openStart = 0.8;

class _TransitionLayer extends StatelessWidget {
  const _TransitionLayer({
    required this.animation,
    required this.module,
    required this.userName,
    required this.snapshot,
  });

  final Animation<double> animation;
  final _ModuleInfo module;
  final String userName;
  final ui.Image? snapshot;

  Animation<double> _interval(double begin, double end, [Curve? curve]) {
    return CurvedAnimation(
      parent: animation,
      curve: Interval(begin, end, curve: curve ?? Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentIn = _interval(0.2, 0.38);
    final contentOut = _interval(0.72, 0.82, Curves.easeInCubic);
    final emblem = _interval(0.3, 0.48, Curves.easeOutBack);
    final greeting = _interval(0.36, 0.52);
    final tag = _interval(0.44, 0.6);

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _IrisPainter(animation, snapshot)),
        AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final opacity = contentIn.value * (1 - contentOut.value);
            if (opacity <= 0) return const SizedBox.shrink();
            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: 1 + 0.06 * contentOut.value,
                child: child,
              ),
            );
          },
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 170,
                    child: CustomPaint(
                      painter: _EmblemPainter(
                        _interval(0.22, 0.5, Curves.easeInOutCubic),
                      ),
                      child: Center(
                        child: ScaleTransition(
                          scale: emblem,
                          child: ClipPath(
                            clipper: const HexagonClipper(),
                            child: Container(
                              width: 88,
                              height: 88,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.brandGoldLight,
                                    AppColors.brandGold,
                                  ],
                                ),
                              ),
                              child: Icon(
                                module.icon,
                                size: 38,
                                color: AppColors.brandBlack,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _Rise(
                    animation: greeting,
                    child: Column(
                      children: [
                        Text(
                          'WELCOME BACK',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.brandGold,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          userName,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.h1.copyWith(
                            color: AppColors.brandWhite,
                            fontSize: 32,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _Rise(
                    animation: tag,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.brandGold.withValues(alpha: 0.6),
                        ),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            module.icon,
                            size: 15,
                            color: AppColors.brandGoldLight,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${module.name.toUpperCase()} WORKSPACE',
                            style: AppTextStyles.labelMedium.copyWith(
                              color: AppColors.brandGoldLight,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  SizedBox(
                    width: 240,
                    height: 14,
                    child: CustomPaint(
                      painter: MeasureProgressPainter(
                        _interval(0.3, 0.78, Curves.easeInOut),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FadeTransition(
                    opacity: tag,
                    child: Text(
                      'Opening ${module.name} dashboard...',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.brandWhite.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Fades a child in while lifting it into place.
class _Rise extends StatelessWidget {
  const _Rise({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - animation.value)),
          child: child,
        ),
      ),
    );
  }
}

// Black hexagonal cover: grows shut over the login page, holds, then opens a
// hexagonal hole onto the dashboard. Gold rings ride the moving edges.
class _IrisPainter extends CustomPainter {
  _IrisPainter(this.animation, this.snapshot) : super(repaint: animation);

  final Animation<double> animation;
  final ui.Image? snapshot;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final center = size.center(Offset.zero);
    // Radius at which a pointy-top hexagon's inner edge clears every corner.
    final fullRadius =
        (size.longestSide / 2 + size.shortestSide / 2) / math.cos(math.pi / 6);

    final Path cover;
    double? edgeRadius;
    var edgeOpacity = 1.0;
    if (t < _closeEnd) {
      final image = snapshot;
      if (image != null) {
        paintImage(
          canvas: canvas,
          rect: Offset.zero & size,
          image: image,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.medium,
        );
      }
      final close = Curves.easeInCubic.transform(t / _closeEnd);
      edgeRadius = fullRadius * close;
      cover = Blueprint.hexagonPath(center, edgeRadius);
    } else if (t < _openStart) {
      cover = Path()..addRect(Offset.zero & size);
    } else {
      final open = Curves.easeInOutCubic.transform(
        (t - _openStart) / (1 - _openStart),
      );
      edgeRadius = fullRadius * open;
      edgeOpacity = 1 - open;
      cover = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addPath(Blueprint.hexagonPath(center, edgeRadius), Offset.zero);
    }

    canvas.drawPath(cover, Paint()..color = AppColors.brandBlack);

    final gridOpacity =
        ((t - 0.15) / 0.2).clamp(0.0, 1.0) *
        (1 - ((t - 0.74) / 0.12).clamp(0.0, 1.0));
    if (gridOpacity > 0) {
      canvas.save();
      canvas.clipPath(cover);
      Blueprint.paintGrid(canvas, size, opacity: gridOpacity);
      Blueprint.paintCornerMarks(canvas, size, opacity: gridOpacity);
      canvas.restore();
    }

    if (edgeRadius != null && edgeRadius > 0) {
      canvas.drawPath(
        Blueprint.hexagonPath(center, edgeRadius),
        Paint()
          ..color = AppColors.brandGold.withValues(alpha: edgeOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      canvas.drawPath(
        Blueprint.hexagonPath(center, edgeRadius * 0.94),
        Paint()
          ..color = AppColors.brandGoldLight.withValues(
            alpha: 0.35 * edgeOpacity,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _IrisPainter oldDelegate) =>
      oldDelegate.animation != animation || oldDelegate.snapshot != snapshot;
}

// Gold outline hexagons and construction lines drawn around the emblem.
class _EmblemPainter extends CustomPainter {
  _EmblemPainter(this.progress) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;

    final construction = Paint()
      ..color = AppColors.brandGold.withValues(alpha: 0.18 * t)
      ..strokeWidth = 1;
    for (final point in Blueprint.hexagonPoints(center, radius)) {
      canvas.drawLine(center, point, construction);
    }

    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius - 1),
      t,
      Paint()
        ..color = AppColors.brandGold.withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    Blueprint.drawPartialPath(
      canvas,
      Blueprint.hexagonPath(center, radius * 0.8),
      ((t - 0.25) / 0.75).clamp(0.0, 1.0),
      Paint()
        ..color = AppColors.brandGold.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _EmblemPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
