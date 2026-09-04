import 'package:flutter/material.dart';

class SalesActionButton extends StatelessWidget {
  const SalesActionButton({
    super.key,
    required this.label,
    this.icon = Icons.add,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed ?? () {},
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
