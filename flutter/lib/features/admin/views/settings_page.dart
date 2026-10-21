import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/features/admin/widgets/admin_settings_form.dart';
import 'package:flutter/material.dart';

/// Store details shown on the admin Settings screen (decision D-03).
///
/// Inlined here rather than read from `AdminMockData`: a "mock data" bag holding
/// the store's own name and contact details made the one screen of real store
/// facts read as fake, and it was the last thing keeping that file alive. There
/// is no settings endpoint — D-03 accepted static text over inventing an API
/// call — so these three constants ARE the store's details this client knows.
///
/// The stocker's `InventorySettingsPage` shows the same literals, because both
/// screens describe the same store.
const _storeName = 'QB Hardware & Construction Supplies';
const _storeEmail = 'contact@qbhardware.com';
const _storePhone = '+63 912 345 6789';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminSkeletonLayout(
      title: 'Settings',
      subtitle: 'Configure general system and store information.',
      selectedNavigationIndex: 7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'General settings',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          AdminSettingsForm(
            storeName: _storeName,
            email: _storeEmail,
            phone: _storePhone,
          ),
        ],
      ),
    );
  }
}
