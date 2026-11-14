import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

/// The same store details the admin Settings screen shows (decisions D-03, D10).
///
/// Inlined instead of read from `AdminMockData`: that bag was deleted in this
/// phase, and these three values are static facts rather than mock data.
const _storeName = 'QB Hardware & Construction Supplies';
const _storeEmail = 'contact@qbhardware.com';
const _storePhone = '+63 912 345 6789';

/// Where the card stops growing on a wide window: three short label/value pairs
/// read better in a column than across 1200 px.
const double _readingWidth = 640;

/// The stocker's Settings tab (decision D4): store details, read-only.
///
/// Shown as a text card, the same look as the admin Settings screen (card A6),
/// because three disabled fields look like a form waiting to be enabled and
/// there is no settings endpoint to enable it (D19).
///
/// Two deliberate omissions:
///  - No `AdminSettingsForm`. That widget ends in a `FilledButton('Save
///    settings')` that is a no-op even for an admin; handing a stocker a save
///    button they are not allowed to use would be a control that lies.
///  - No API call. Settings has no backend at all, so the values below are the
///    same literals the admin Settings screen shows.
class InventorySettingsPage extends StatelessWidget {
  const InventorySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return InventorySkeletonLayout(
      title: 'Settings',
      subtitle: 'Store details this system keeps.',
      selectedNavigationIndex: 12,
      onNavigationSelected: (index) => navigateInventory(context, index),
      // A full width card on a 1440 window is three short lines with empty space
      // beside them, so the card keeps a reading width there. Below that width
      // it fills the content area instead of leaving a strip of dead space.
      child: LayoutBuilder(
        builder: (context, slot) => Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: slot.maxWidth < _readingWidth
                ? double.infinity
                : _readingWidth,
            child: AppPanel(
              title: 'Store information',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Field(label: 'Store name', value: _storeName),
                  const SizedBox(height: AppSpacing.lg),
                  const _Field(label: 'Contact email', value: _storeEmail),
                  const SizedBox(height: AppSpacing.lg),
                  const _Field(label: 'Contact number', value: _storePhone),
                  const SizedBox(height: AppSpacing.lg),
                  // Read-only on purpose: a field the stocker could type in, or a
                  // Save button with nothing behind it, would promise an editing
                  // path the system does not have for this role.
                  const Text(
                    'Store settings are managed by your store manager.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One labelled store fact. The label sits above the value so a long store name
/// wraps inside the card instead of shortening next to a fixed label column.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}
