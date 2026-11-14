import 'package:flutter/material.dart';

/// A secondary action, driven entirely by its callback.
///
/// `onPressed` is passed straight through: a caller who supplies no callback
/// gets a **disabled** button, which Flutter renders as such. The old
/// `onPressed ?? () {}` default produced an enabled button that swallowed the
/// press and did nothing — the dead-control shape removed in Phase 3 Task 0.
class InventoryActionButton extends StatelessWidget {
  const InventoryActionButton({
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
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
