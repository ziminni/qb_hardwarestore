import 'package:flutter/material.dart';

class MockAction extends StatelessWidget {
  const MockAction({super.key, required this.label, this.icon = Icons.add});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () {},
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
