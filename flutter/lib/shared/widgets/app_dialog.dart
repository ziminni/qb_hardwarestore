import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:client/shared/widgets/measure_ruler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The one dialog frame for the whole app: a hexagon icon badge and title, a
/// ruler edge, a body that scrolls when it has to, and a footer bar for the
/// actions.
///
/// Three things are wired in here and not left to each caller, because they are
/// what the plan's HCI acceptance asks of every dialog:
///   - Tab runs header, then the body's fields in reading order, then the
///     footer actions: that is simply the order of the widgets below, so keep
///     the close button in the header and the actions in `actions`;
///   - Esc closes it from anywhere inside, including from a text field;
///   - the router pops it with no result, and Flutter hands focus back to the
///     button that opened it.
///
/// Closing pops the route, so a caller that needs a value passes its own
/// result through `Navigator.pop(context, value)` from a footer button.
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

  /// Sits left of the close button, for a status pill or a step counter.
  final Widget? headerTrailing;

  final Widget content;

  /// Footer buttons, right aligned. Empty means no footer bar at all.
  final List<Widget> actions;

  /// Ceiling for the dialog's width. The window caps it from below on a short
  /// screen and the inset padding caps it on a narrow one.
  final double width;

  /// Set to false when [content] manages its own height and scrolling (a list
  /// inside a fixed-height box, usually).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      // The dialog takes focus when it opens, so a keyboard user lands inside
      // it and Esc reaches the shortcut above.
      child: Focus(
        autofocus: true,
        child: Dialog(
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
                // Cinzel: the 20 px dialog title is a heading, not body text.
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
          if (trailing case final trailing?) ...[
            const SizedBox(width: AppSpacing.md),
            trailing,
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

/// Black hexagon with a gold icon: the dialog header mark, and the same shape
/// the splash and login screens draw.
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

/// Gold small-caps label with a hairline, separating groups inside a dialog.
///
/// The ink is [AppColors.brandGoldText]: the brand gold itself is a fill colour
/// and sits under 4.5:1 as 11 px text on white.
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
              color: AppColors.brandGoldText,
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

/// Numbered step heading for a multi-part form: a gold hexagon with the step
/// number and the step's question.
///
/// Open Sans on purpose: the step title is 15 px, and Cinzel is reserved for
/// headings of 18 px and up. Cinzel at this size reads as a mistake next to the
/// form's fields, which are all Open Sans.
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
          Flexible(
            child: Text(
              title,
              style: AppTextStyles.labelLarge.copyWith(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(child: Divider(height: 1)),
        ],
      ),
    );
  }
}

/// Label and value pair for a read-only detail view.
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

  /// The label column's width, so values line up down the list. A form that
  /// needs more room for its labels widens all of them, not just one.
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

/// The gold total under a list of lines.
///
/// It takes the [amount] as a number and prints it through [formatPeso], so a
/// total cannot drift from the rest of the app's money format. The figure is
/// Cinzel: a total is the one number on the screen worth a figure face.
class TotalBar extends StatelessWidget {
  const TotalBar({super.key, required this.label, required this.amount});

  final String label;
  final num amount;

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
          // The label takes the left of the bar and pushes the figure to the
          // right edge, so the total lines up down a column of bars.
          Expanded(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.brandGold,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            formatPeso(amount),
            style: const TextStyle(
              fontFamily: AppTextStyles.cinzelFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.brandGoldLight,
            ),
          ),
        ],
      ),
    );
  }
}

/// A neutral note with a gold edge, for guidance inside a form.
///
/// Neutral on purpose: this is a hint, not a result. [ErrorBanner] is the loud
/// sibling and keeps its own red; a warning would use the warning tint. The ink
/// is [AppColors.textPrimary] on the sunken surface, which clears 4.5:1.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.title,
    this.icon = Icons.info_outline_rounded,
  });

  final String message;
  final String? title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: const Border(
          left: BorderSide(color: AppColors.brandGold, width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.brandGoldText),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Text(
                  message,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
