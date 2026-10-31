import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

/// Store details shown on the admin Settings screen (decisions D-03, D10).
///
/// Inlined here rather than read from `AdminMockData`: a "mock data" bag holding
/// the store's own name and contact details made the one screen of real store
/// facts read as fake, and it was the last thing keeping that file alive. There
/// is no settings endpoint (D19), so these three constants ARE the store's
/// details this client knows, and D10 keeps them as they are until the store
/// confirms them.
///
/// The stocker's `InventorySettingsPage` shows the same literals, because both
/// screens describe the same store.
const _storeName = 'QB Hardware & Construction Supplies';
const _storeEmail = 'contact@qbhardware.com';
const _storePhone = '+63 912 345 6789';

/// Where the card stops growing on a wide window: three short label/value pairs
/// read better in a column than across 1200 px.
const double _readingWidth = 640;

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminSkeletonLayout(
      title: 'Settings',
      subtitle: 'Store details this system keeps.',
      selectedNavigationIndex: 7,
      // A full width card on a 1440 window is three short lines with empty
      // space beside them, so the card keeps a reading width there. Below that
      // width it fills the content area: a 640 px box in a 760 window used to
      // stop short and leave a strip of dead space on the right.
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
                  // Read-only on purpose: a field the admin could type in, or a
                  // Save button with nothing behind it, would promise an
                  // editing path the system does not have.
                  const Text(
                    'Editing store details is not available yet.',
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
