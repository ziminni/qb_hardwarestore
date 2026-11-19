import 'package:client/core/theme/app_scroll_behavior.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/core/theme/theme_settings_controller.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/widget/login_transition_overlay.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.auth});

  final AuthViewmodel auth;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final GoRouter _router = AppRoutes.createRouter(widget.auth);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeSettingsController.instance,
      builder: (context, _) {
        final settings = ThemeSettingsController.instance.settings;
        return MaterialApp.router(
          title: 'Hardware Store Management System',
          theme: AppTheme.buildTheme(settings),
          // Wide tables must be reachable with a plain mouse on a 1366px screen.
          scrollBehavior: const AppScrollBehavior(),
          debugShowCheckedModeBanner: false,
          routerConfig: _router,
          // Sits above every route so it can cover the login-to-dashboard swap.
          // Also applies this device's local display-scale preference on top of
          // the OS accessibility scale.
          builder: (context, child) {
            final media = MediaQuery.of(context);
            final scaleFactor = settings.displayScale.factor;
            final scaled = scaleFactor == 1.0
                ? media
                : media.copyWith(
                    textScaler: TextScaler.linear(
                      media.textScaler.scale(1.0) * scaleFactor,
                    ),
                  );
            return MediaQuery(
              data: scaled,
              child: LoginTransitionOverlay(
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        );
      },
    );
  }
}
