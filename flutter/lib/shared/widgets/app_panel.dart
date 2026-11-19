import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// The surface card every page is built from: the same panel the till uses.
///
/// Border, radius and padding are fixed on purpose. Reads [AppPalette] so it
/// adapts cleanly when the local device switches theme or appearance mode.
class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.child, this.title, this.trailing});

  /// Inside the border, on every side.
  static const double padding = 18;

  /// What the panel's own frame takes, border and padding on both sides. A
  /// child that must fill a panel handed a fixed slot subtracts this; the panel
  /// itself stays free of layout callbacks so equal-height rows can still ask
  /// it for its intrinsic size.
  static const double chrome = padding * 2 + 2;

  final Widget child;

  /// Panel heading, left of [trailing] when one is given.
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final header = title == null && trailing == null
        ? null
        : Row(
            children: [
              if (title != null)
                Expanded(
                  child: Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppTextStyles.cinzelFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: p.textPrimary,
                    ),
                  ),
                ),
              ?trailing,
            ],
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.cardBackground,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: Padding(
        padding: const EdgeInsets.all(padding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) ...[
              header,
              const SizedBox(height: AppSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
