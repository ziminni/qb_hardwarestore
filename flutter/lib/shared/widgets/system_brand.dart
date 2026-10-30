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
    this.showName = true,
  });

  final double logoSize;
  final double fontSize;
  final Color? textColor;
  final bool uppercase;
  final String? subtitle;

  /// False shows the logo alone, for the collapsed icon rail.
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logo = Image.asset(
      AppAssets.logo,
      width: logoSize,
      height: logoSize,
      fit: BoxFit.contain,
      // Decode at the size it is shown (times the screen density), not the
      // file's full size, on every page that draws the sidebar.
      cacheWidth: (logoSize * MediaQuery.devicePixelRatioOf(context)).round(),
      semanticLabel: 'Queen Builders logo',
    );
    if (!showName) return logo;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
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
