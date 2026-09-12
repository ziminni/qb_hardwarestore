import 'dart:ui';

import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class LoginGlassCard extends StatelessWidget {
  const LoginGlassCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(AppSpacing.xxl),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
          ),
          child: child,
        ),
      ),
    );
  }
}
