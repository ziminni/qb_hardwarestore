import 'package:client/shared/widgets/stat_tile.dart';
import 'package:flutter/material.dart';

class InventoryMovementSummaryCard extends StatelessWidget {
  const InventoryMovementSummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StatTile(
      icon: icon,
      label: label,
      value: value,
      caption: caption,
      color: color,
    );
  }
}
