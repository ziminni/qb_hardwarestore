import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:flutter/material.dart';

/// The heading above a list or a block of tiles: a small gold mark, the title,
/// an optional line of context, and any actions the caller wants on the right.
///
/// This is the one copy. Two private `_SectionHeading` widgets grew in the
/// dashboard and the reports page; they are replaced by this one.
///
/// The title is Cinzel at 18 px, which is the floor for Cinzel: anything
/// smaller is set in Open Sans like the rest of the interface text.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;

  /// One line under the title: a period, a count, or where the rows come from.
  final String? subtitle;

  /// Buttons or a pill for the right of the heading. They wrap under the title
  /// rather than squeezing it on a narrow window.
  final List<Widget> actions;

  static const double titleSize = 18;

  /// The mark beside the title, as wide as the category card's active bar.
  static const double markWidth = 3;
  static const double markHeight = 16;

  @override
  Widget build(BuildContext context) {
    final title_ = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontFamily: AppTextStyles.cinzelFont,
        fontSize: titleSize,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
    final subtitle_ = subtitle;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: markWidth,
            height: markHeight,
            margin: const EdgeInsets.only(top: 4, right: AppSpacing.sm + 2),
            decoration: BoxDecoration(
              color: AppColors.brandGold,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: title_),
                if (subtitle_ != null)
                  Text(
                    subtitle_,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.md),
            Wrap(spacing: AppSpacing.sm, children: actions),
          ],
        ],
      ),
    );
  }
}
