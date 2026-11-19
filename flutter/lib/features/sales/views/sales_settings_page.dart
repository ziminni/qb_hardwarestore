import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/shared/widgets/settings_side_layout.dart';
import 'package:client/shared/widgets/system_settings_panel.dart';
import 'package:flutter/material.dart';

/// The Store Manager's Settings screen, laid out identically to Admin, POS, and
/// Stock Manager Settings: grouped side tabs on the left (Store information +
/// local System settings) and the open section on the right.
class SalesSettingsPage extends StatelessWidget {
  const SalesSettingsPage({super.key});

  static final List<SettingsSideSection> _sections = [
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
        sections: _sections,
      ),
    );
  }
}
