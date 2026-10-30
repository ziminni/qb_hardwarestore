import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:flutter/material.dart';

// Bordered panel for a data table: optional titled header with a record
// count, full-width horizontally scrollable body, empty state, and footer.
class DataPanel extends StatelessWidget {
  const DataPanel({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.count,
    this.trailing,
    this.isEmpty = false,
    this.emptyIcon = Icons.inventory_2_outlined,
    this.emptyTitle = 'Nothing to show',
    this.emptyMessage,
    this.emptyAction,
    this.footer,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final int? count;
  final List<Widget>? trailing;
  final bool isEmpty;
  final IconData emptyIcon;
  final String emptyTitle;
  final String? emptyMessage;
  final Widget? emptyAction;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.brandGold,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title!,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.labelLarge.copyWith(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (count != null) ...[
                              const SizedBox(width: AppSpacing.sm),
                              CountPill(count: count!),
                            ],
                          ],
                        ),
                        if (subtitle != null)
                          Text(subtitle!, style: AppTextStyles.bodySmall),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: trailing!,
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          if (isEmpty)
            EmptyState(
              icon: emptyIcon,
              title: emptyTitle,
              message: emptyMessage,
              action: emptyAction,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: child,
                ),
              ),
            ),
          if (footer != null) ...[
            const Divider(height: 1),
            Container(color: AppColors.tableHeader, child: footer),
          ],
        ],
      ),
    );
  }
}

// Small dark pill showing a record count.
class CountPill extends StatelessWidget {
  const CountPill({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.brandBlack,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        '$count',
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.brandGoldLight,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// Centered placeholder with an outlined gold hexagon around the icon.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 64,
            child: CustomPaint(
              painter: const _HexOutlinePainter(),
              child: Icon(icon, size: 26, color: AppColors.brandGold),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.labelLarge.copyWith(fontSize: 15),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall.copyWith(fontSize: 13),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

class _HexOutlinePainter extends CustomPainter {
  const _HexOutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawPath(
      Blueprint.hexagonPath(center, radius),
      Paint()..color = AppColors.selected,
    );
    canvas.drawPath(
      Blueprint.hexagonPath(center, radius - 1),
      Paint()
        ..color = AppColors.brandGold.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _HexOutlinePainter oldDelegate) => false;
}
