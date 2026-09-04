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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            initialValue: storeName,
            decoration: const InputDecoration(
              labelText: 'Store name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: email,
            decoration: const InputDecoration(
              labelText: 'Contact email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            initialValue: phone,
            decoration: const InputDecoration(
              labelText: 'Contact number',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () {},
              child: const Text('Save settings'),
            ),
          ),
        ],
      ),
    );
  }
}
