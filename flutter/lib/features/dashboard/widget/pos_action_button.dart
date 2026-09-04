import 'package:flutter/material.dart';

class PosActionButton extends StatelessWidget {
  const PosActionButton({
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
