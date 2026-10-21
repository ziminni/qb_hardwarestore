import 'package:flutter/material.dart';

class AdminSettingsForm extends StatelessWidget {
  const AdminSettingsForm({
    super.key,
    required this.storeName,
    required this.email,
    required this.phone,
  });

  final String storeName;
  final String email;
  final String phone;

  @override
  Widget build(BuildContext context) {
    // Read-only: no settings endpoint exists (D-03). Fields disabled, no Save
    // button — an editable form with a dead Save would lie to the admin.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            initialValue: storeName,
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'Store name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: email,
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'Contact email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: phone,
            enabled: false,
            decoration: const InputDecoration(
              labelText: 'Contact number',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}
