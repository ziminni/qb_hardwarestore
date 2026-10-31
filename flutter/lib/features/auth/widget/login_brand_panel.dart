import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
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
      color: AppColors.brandBlack,
      child: Padding(
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
    );
  }
}
