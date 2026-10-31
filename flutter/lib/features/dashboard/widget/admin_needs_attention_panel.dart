import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

/// One thing waiting for the admin: what it is, how many, and the screen that
/// can clear it.
class AdminAttentionItem {
  const AdminAttentionItem({
    required this.label,
    required this.value,
    required this.actionLabel,
    required this.onAction,
  });

  final String label;

  /// Already formatted by the caller (a count through `formatCount`).
  final String value;

  /// Worded by the caller, because "Review requisitions" and "Open monitoring"
  /// are different jobs.
  final String actionLabel;
  final VoidCallback onAction;
}

/// What waits on the admin, each line with the one action it needs.
///
/// The four "Quick actions" are gone: three repeated the sidebar and the fourth
/// ("Add product") pointed at a products screen the admin cannot open, so it
/// looked live and did nothing (D11). What is left here is work.
class AdminNeedsAttentionPanel extends StatelessWidget {
  const AdminNeedsAttentionPanel({super.key, required this.items});

  final List<AdminAttentionItem> items;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      title: 'Needs attention',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0)
              const Divider(height: AppSpacing.xl, color: AppColors.border),
            _AttentionRow(item: items[index]),
          ],
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  const _AttentionRow({required this.item});

  final AdminAttentionItem item;

  @override
  Widget build(BuildContext context) {
    // The label takes its own line and the count sits beside the action, so a
    // long label wraps instead of squeezing the button off the narrow column.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          item.label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Text(
              item.value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const Spacer(),
            TextButton(onPressed: item.onAction, child: Text(item.actionLabel)),
          ],
        ),
      ],
    );
  }
}
