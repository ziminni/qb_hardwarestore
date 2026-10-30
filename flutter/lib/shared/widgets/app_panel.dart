import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:flutter/material.dart';

/// The white card every page is built from: the same panel the till uses.
///
/// Border, radius and padding are fixed on purpose. Pages used to mix `Card`,
/// `Container` and `DecoratedBox` with five different paddings, and that is
/// exactly what made the screens look unfinished next to the canvas.
class AppPanel extends StatelessWidget {
  const AppPanel({super.key, required this.child, this.title, this.trailing});

  /// Inside the border, on every side.
  static const double padding = 18;

  final Widget child;

  /// Panel heading, left of [trailing] when one is given.
  final String? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
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
                    style: const TextStyle(
                      fontFamily: AppTextStyles.cinzelFont,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ?trailing,
            ],
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
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
