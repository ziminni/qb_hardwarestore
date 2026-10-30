import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:client/shared/widgets/measure_ruler.dart';
import 'package:flutter/material.dart';

// Branded modal frame: icon badge + title header, ruler edge, scrolling body,
// and a footer bar for actions. Closing it pops with no result.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.content,
    this.subtitle,
    this.headerTrailing,
    this.actions = const [],
    this.width = 520,
    this.scrollable = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? headerTrailing;
  final Widget content;
  final List<Widget> actions;
  final double width;

  // Set to false when [content] manages its own height and scrolling.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Dialog(
      backgroundColor: AppColors.cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: AppColors.brandBlack.withValues(alpha: 0.25),
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.large),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DialogHeader(
              icon: icon,
              title: title,
              subtitle: subtitle,
              trailing: headerTrailing,
            ),
            const MeasureRuler(height: 6),
            Flexible(
              child: scrollable
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: content,
                    )
                  : Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: content,
                    ),
            ),
            if (actions.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.lg,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceSunken,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.sm,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          HexIconBadge(icon: icon),
          const SizedBox(width: AppSpacing.md + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h3.copyWith(height: 1.2),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: AppTextStyles.bodySmall),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

// Black hexagon with a gold icon, used as the dialog header mark.
class HexIconBadge extends StatelessWidget {
  const HexIconBadge({super.key, required this.icon, this.size = 44});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const HexagonClipper(),
      child: Container(
        width: size,
        height: size,
        color: AppColors.brandBlack,
        alignment: Alignment.center,
        child: Icon(icon, size: size * 0.45, color: AppColors.brandGoldLight),
      ),
    );
  }
}

// Gold small-caps label with a hairline, separating groups in a dialog.
class DialogSectionLabel extends StatelessWidget {
  const DialogSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.brandGold,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(child: Divider(height: 1)),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// Numbered step heading for multi-part forms.
class FormStepHeader extends StatelessWidget {
  const FormStepHeader({super.key, required this.step, required this.title});

  final int step;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          ClipPath(
            clipper: const HexagonClipper(),
            child: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.brandGoldLight, AppColors.brandGold],
                ),
              ),
              child: Text(
                '$step',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.brandBlack,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            title,
            style: AppTextStyles.h4.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}

// Label / value pair for read-only detail views.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
    this.labelWidth = 150,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceMuted)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.labelLarge.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}

// Row for an order or sale line: item, details, and amount.
class LineItemTile extends StatelessWidget {
  const LineItemTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.icon = Icons.inventory_2_outlined,
  });

  final String title;
  final String subtitle;
  final String amount;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceMuted)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.selected,
              borderRadius: BorderRadius.circular(AppRadii.small),
            ),
            child: Icon(icon, size: 18, color: AppColors.brandGold),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelLarge),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            amount,
            style: AppTextStyles.labelLarge.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// Black summary bar with a gold label, for totals.
class TotalBar extends StatelessWidget {
  const TotalBar({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandBlack,
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Row(
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.brandGold,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTextStyles.bodyLarge.copyWith(
              color: AppColors.brandWhite,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// Tinted note with a colored edge, for hints and results.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.info_outline_rounded,
    this.color = AppColors.brandGold,
  });

  final String message;
  final String? title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: AppTextStyles.labelLarge),
                  const SizedBox(height: 2),
                ],
                Text(message, style: AppTextStyles.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
