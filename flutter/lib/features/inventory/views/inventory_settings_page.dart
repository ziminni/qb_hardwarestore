import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/features/admin/viewmodels/admin_mock_data.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:flutter/material.dart';

/// The stocker's Settings tab (decision D-03): store details, read-only.
///
/// Two deliberate omissions:
///  - No `AdminSettingsForm`. That widget ends in a `FilledButton('Save
///    settings')` that is a no-op even for an admin; handing a stocker a save
///    button they are not allowed to use would be a control that lies.
///  - No API call. Settings has no backend at all, so the values below are the
///    same literals the admin Settings screen shows.
///
/// The fields are `enabled: false` rather than plain text so they still read as
/// the form they describe.
class InventorySettingsPage extends StatelessWidget {
  const InventorySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InventorySkeletonLayout(
      title: 'Settings',
      subtitle: 'Store information.',
      selectedNavigationIndex: 12,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Store settings are managed by your store manager.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              initialValue: AdminMockData.storeName,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Store name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              initialValue: AdminMockData.storeEmail,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Contact email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              initialValue: AdminMockData.storePhone,
              enabled: false,
              decoration: const InputDecoration(
                labelText: 'Contact number',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
