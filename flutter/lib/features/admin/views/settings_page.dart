import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/features/admin/viewmodels/admin_mock_data.dart';
import 'package:client/features/admin/widgets/admin_settings_form.dart';
import 'package:flutter/material.dart';

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
            storeName: AdminMockData.storeName,
            email: AdminMockData.storeEmail,
            phone: AdminMockData.storePhone,
          ),
        ],
      ),
    );
  }
}
