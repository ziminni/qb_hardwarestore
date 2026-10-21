import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:flutter/material.dart';

/// The stocker's Reports tab (decision D-02): an access message, not a screen.
///
/// Every `/api/v1/reports/*` endpoint is `IsManagerRole`-gated, so a stocker
/// would get a 403. Rendering a spinner that fails, or an empty table, would
/// read as "the store made no money this month" — the more expensive lie. So
/// this page makes NO API call and says plainly who can see reports.
///
/// If the reports are ever opened to the `inventory` role, this page is the one
/// place to replace.
class InventoryReportsPage extends StatelessWidget {
  const InventoryReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InventorySkeletonLayout(
      title: 'Reports',
      subtitle: 'Management reports.',
      selectedNavigationIndex: 11,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 72),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 64,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                'Reports are available to Store Managers and above.',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Ask your manager for a summary.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
