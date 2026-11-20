import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/features/inventory/controllers/inventory_settings_controller.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/pos/controllers/pos_lock_settings_controller.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/settings_side_layout.dart';
import 'package:client/shared/widgets/system_settings_panel.dart';
import 'package:flutter/material.dart';

/// The stocker's Settings tab (decision D4), laid out identically to Admin &
/// POS Settings: grouped side tabs on the left and the open section on the
/// right.
class InventorySettingsPage extends StatelessWidget {
  const InventorySettingsPage({super.key, this.controller});

  /// Injected by tests; defaults to [InventorySettingsController.instance].
  final InventorySettingsController? controller;

  List<SettingsSideSection> _buildSections() {
    final ctrl = controller ?? InventorySettingsController.instance;
    return [
      SettingsSideSection(
        id: 'store',
        label: 'Store information',
        icon: Icons.storefront_outlined,
        description: 'The name and contact details printed for this store.',
        group: 'Store',
        builder: (_) => const StoreInformationPanel(
          footerNote: 'Store settings are managed by your store manager.',
        ),
      ),
      SettingsSideSection(
        id: 'warehouse',
        label: 'Stock & receiving',
        icon: Icons.inventory_2_outlined,
        description:
            'Default adjustment reasons, product sorting, scanner behavior, '
            'and quick-count steps on this warehouse device.',
        group: 'Warehouse',
        builder: (_) => _InventoryWarehousePanel(controller: ctrl),
      ),
      SettingsSideSection(
        id: 'security',
        label: 'Security & lock',
        icon: Icons.lock_outline_rounded,
        description:
            'Automatically lock shared warehouse terminals after inactivity.',
        group: 'Security',
        builder: (_) => _InventorySecurityPanel(controller: ctrl),
      ),
      SettingsSideSection(
        id: 'system',
        label: 'System settings',
        icon: Icons.palette_outlined,
        description:
            'Customize the theme, accent palette, sidebar finish, and display '
            'comfort for this device.',
        group: 'System',
        builder: (_) => const SystemSettingsPanel(
          key: ValueKey('inventory-settings-system'),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return InventorySkeletonLayout(
      title: 'Settings',
      subtitle: 'Store details and local device preferences.',
      selectedNavigationIndex: AppDestinations.indexOf(
        'inventory.settings',
        AppAreas.inventory,
      ),
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: SettingsSideLayout(
        keyPrefix: 'inventory-settings',
        sections: _buildSections(),
      ),
    );
  }
}

class _InventoryWarehousePanel extends StatefulWidget {
  const _InventoryWarehousePanel({required this.controller});

  final InventorySettingsController controller;

  @override
  State<_InventoryWarehousePanel> createState() =>
      _InventoryWarehousePanelState();
}

class _InventoryWarehousePanelState extends State<_InventoryWarehousePanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPanel(
              title: 'Receiving & stock movements',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set defaults for stock adjustments and product listing '
                    'order.',
                    style: TextStyle(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: [
                      SizedBox(
                        width: 260,
                        child:
                            DropdownButtonFormField<InventoryAdjustmentReason>(
                          key: const ValueKey(
                            'inventory-default-reason-dropdown',
                          ),
                          initialValue: c.defaultAdjustmentReason,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Default adjustment reason',
                            prefixIcon: Icon(Icons.edit_note_outlined),
                          ),
                          items: [
                            for (final reason
                                in InventoryAdjustmentReason.values)
                              DropdownMenuItem(
                                value: reason,
                                child: Text(reason.label),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) c.setDefaultAdjustmentReason(v);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<InventoryProductSort>(
                          key: const ValueKey('inventory-product-sort-dropdown'),
                          initialValue: c.defaultProductSort,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Default product sort',
                            prefixIcon: Icon(Icons.sort_outlined),
                          ),
                          items: [
                            for (final sort in InventoryProductSort.values)
                              DropdownMenuItem(
                                value: sort,
                                child: Text(sort.label),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) c.setDefaultProductSort(v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      key: const ValueKey('inventory-confirm-large-adj-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Confirm large stock adjustments'),
                      subtitle: const Text(
                        'Show a confirmation prompt for adjustments of 50+ '
                        'units',
                      ),
                      value: c.confirmLargeAdjustments,
                      onChanged: c.setConfirmLargeAdjustments,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPanel(
              title: 'Scanner & counting',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: DropdownButtonFormField<int>(
                      key: const ValueKey('inventory-quick-count-dropdown'),
                      initialValue: c.quickCountStep,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Quick-count step',
                        prefixIcon: Icon(Icons.exposure_plus_1_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('+1 unit')),
                        DropdownMenuItem(value: 5, child: Text('+5 units')),
                        DropdownMenuItem(value: 10, child: Text('+10 units')),
                      ],
                      onChanged: (v) {
                        if (v != null) c.setQuickCountStep(v);
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        SwitchListTile(
                          key: const ValueKey('inventory-auto-focus-switch'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Auto-focus barcode search'),
                          subtitle: const Text(
                            'Keep the SKU/barcode field ready during receiving',
                          ),
                          value: c.autoFocusBarcodeSearch,
                          onChanged: c.setAutoFocusBarcodeSearch,
                        ),
                        SwitchListTile(
                          key: const ValueKey('inventory-sound-feedback-switch'),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Sound feedback'),
                          subtitle: const Text(
                            'Play a chime when scanning or logging stock',
                          ),
                          value: c.soundFeedback,
                          onChanged: c.setSoundFeedback,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _InventorySecurityPanel extends StatefulWidget {
  const _InventorySecurityPanel({required this.controller});

  final InventorySettingsController controller;

  @override
  State<_InventorySecurityPanel> createState() =>
      _InventorySecurityPanelState();
}

class _InventorySecurityPanelState extends State<_InventorySecurityPanel> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        return AppPanel(
          title: 'Automatic lock',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Lock the warehouse terminal automatically after no pointer '
                'or scroll activity for the selected duration.',
                style: TextStyle(color: p.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: DropdownButtonFormField<PosAutoLockOption>(
                  key: const ValueKey('inventory-auto-lock-dropdown'),
                  initialValue: c.autoLockOption,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Auto-lock after',
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  items: [
                    for (final option in PosAutoLockOption.values)
                      DropdownMenuItem(
                        value: option,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) c.setAutoLockOption(v);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              Material(
                type: MaterialType.transparency,
                child: SwitchListTile(
                  key: const ValueKey('inventory-lock-shortcut-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Quick-lock keyboard shortcut'),
                  subtitle: const Text(
                    'Press Ctrl+L or Cmd+L to lock immediately',
                  ),
                  value: c.lockShortcutEnabled,
                  onChanged: c.setLockShortcutEnabled,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
