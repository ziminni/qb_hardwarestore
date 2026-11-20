import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/features/pos/controllers/pos_lock_settings_controller.dart';
import 'package:client/features/sales/controllers/sales_settings_controller.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/settings_side_layout.dart';
import 'package:client/shared/widgets/system_settings_panel.dart';
import 'package:flutter/material.dart';

/// The Store Manager's Settings screen, laid out identically to Admin, POS, and
/// Stock Manager Settings: grouped side tabs on the left and the open section
/// on the right.
class SalesSettingsPage extends StatelessWidget {
  const SalesSettingsPage({super.key, this.controller});

  /// Injected by tests; defaults to [SalesSettingsController.instance].
  final SalesSettingsController? controller;

  List<SettingsSideSection> _buildSections() {
    final ctrl = controller ?? SalesSettingsController.instance;
    return [
      SettingsSideSection(
        id: 'store',
        label: 'Store information',
        icon: Icons.storefront_outlined,
        description: 'The name and contact details printed for this store.',
        group: 'Store',
        builder: (_) => const StoreInformationPanel(
          footerNote: 'Store settings are managed by a System Administrator.',
        ),
      ),
      SettingsSideSection(
        id: 'reports',
        label: 'Reports & oversight',
        icon: Icons.assessment_outlined,
        description:
            'Default report date ranges, export formats, collectibles alerts, '
            'and margin privacy for this device.',
        group: 'Operations',
        builder: (_) => _SalesOperationsPanel(controller: ctrl),
      ),
      SettingsSideSection(
        id: 'security',
        label: 'Security & lock',
        icon: Icons.lock_outline_rounded,
        description:
            'Automatically lock the manager screen after inactivity to protect '
            'sales and financial data.',
        group: 'Security',
        builder: (_) => _SalesSecurityPanel(controller: ctrl),
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
          key: ValueKey('sales-settings-system'),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SalesSkeletonLayout(
      title: 'Settings',
      subtitle: 'Store details and local device preferences.',
      selectedNavigationIndex: AppDestinations.indexOf(
        'sales.settings',
        AppAreas.sales,
      ),
      onNavigationSelected: (index) => navigateSales(context, index),
      child: SettingsSideLayout(
        keyPrefix: 'sales-settings',
        sections: _buildSections(),
      ),
    );
  }
}

class _SalesOperationsPanel extends StatefulWidget {
  const _SalesOperationsPanel({required this.controller});

  final SalesSettingsController controller;

  @override
  State<_SalesOperationsPanel> createState() => _SalesOperationsPanelState();
}

class _SalesOperationsPanelState extends State<_SalesOperationsPanel> {
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
              title: 'Reports & exports',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pre-select your preferred reporting window and export '
                    'format on this computer.',
                    style: TextStyle(color: p.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: [
                      SizedBox(
                        width: 260,
                        child: DropdownButtonFormField<SalesDefaultReportRange>(
                          key: const ValueKey('sales-default-range-dropdown'),
                          initialValue: c.defaultReportRange,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Default report range',
                            prefixIcon: Icon(Icons.date_range_outlined),
                          ),
                          items: [
                            for (final range in SalesDefaultReportRange.values)
                              DropdownMenuItem(
                                value: range,
                                child: Text(range.label),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) c.setDefaultReportRange(v);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<SalesDefaultExportFormat>(
                          key: const ValueKey('sales-default-export-dropdown'),
                          initialValue: c.defaultExportFormat,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Default export format',
                            prefixIcon: Icon(Icons.download_outlined),
                          ),
                          items: [
                            for (final fmt in SalesDefaultExportFormat.values)
                              DropdownMenuItem(
                                value: fmt,
                                child: Text(fmt.label),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) c.setDefaultExportFormat(v);
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
                      key: const ValueKey('sales-mask-cost-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mask cost & margin columns'),
                      subtitle: const Text(
                        'Hide unit cost and profit figures when sharing your '
                        'screen',
                      ),
                      value: c.maskCostAndMargin,
                      onChanged: c.setMaskCostAndMargin,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPanel(
              title: 'Collectibles & oversight',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 260),
                    child: DropdownButtonFormField<int>(
                      key: const ValueKey('sales-overdue-days-dropdown'),
                      initialValue: c.overdueAlertDays,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Overdue utang alert threshold',
                        prefixIcon: Icon(Icons.schedule_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('3 days')),
                        DropdownMenuItem(value: 7, child: Text('7 days')),
                        DropdownMenuItem(value: 14, child: Text('14 days')),
                        DropdownMenuItem(value: 30, child: Text('30 days')),
                      ],
                      onChanged: (v) {
                        if (v != null) c.setOverdueAlertDays(v);
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  Material(
                    type: MaterialType.transparency,
                    child: SwitchListTile(
                      key: const ValueKey('sales-confirm-discounts-switch'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Require confirmation on large discounts / voids',
                      ),
                      subtitle: const Text(
                        'Show an extra prompt before approving high-value '
                        'overrides',
                      ),
                      value: c.confirmLargeDiscounts,
                      onChanged: c.setConfirmLargeDiscounts,
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

class _SalesSecurityPanel extends StatefulWidget {
  const _SalesSecurityPanel({required this.controller});

  final SalesSettingsController controller;

  @override
  State<_SalesSecurityPanel> createState() => _SalesSecurityPanelState();
}

class _SalesSecurityPanelState extends State<_SalesSecurityPanel> {
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
                'Lock the manager workspace automatically after no pointer or '
                'scroll activity for the selected duration.',
                style: TextStyle(color: p.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: DropdownButtonFormField<PosAutoLockOption>(
                  key: const ValueKey('sales-auto-lock-dropdown'),
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
                  key: const ValueKey('sales-lock-shortcut-switch'),
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
