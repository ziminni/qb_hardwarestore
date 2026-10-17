import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class SystemBrand extends StatelessWidget {
  const SystemBrand({
    super.key,
    this.logoSize = 40,
    this.fontSize = 15,
    this.textColor,
    this.uppercase = false,
    this.subtitle,
  });

  final double logoSize;
  final double fontSize;
  final Color? textColor;
  final bool uppercase;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          AppAssets.logo,
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
          semanticLabel: 'Queen Builders logo',
        ),
        const SizedBox(width: AppSpacing.sm),
        // Flexible + ellipsis because this brand sits in a FIXED-width sidebar (220px in
        // DashboardShell) with no defence of its own: the Row asks for its intrinsic width, so
        // a longer subtitle, a larger accessibility text scale, or simply a wider font overflows
        // it. A widget test found it rather than a device, because the test's fallback font is
        // wider - but the widget is structurally undefended either way, and truncation engages
        // only when the text would not have fitted.
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                uppercase ? 'QUEEN BUILDERS' : 'Queen Builders',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: textColor,
                  fontFamily: 'Cinzel',
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppColors.brandGold,
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.35,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
