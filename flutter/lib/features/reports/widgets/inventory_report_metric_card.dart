import 'package:client/shared/widgets/stat_tile.dart';
import 'package:flutter/material.dart';

class InventoryReportMetricCard extends StatelessWidget {
  const InventoryReportMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return StatTile(icon: icon, label: label, value: value);
  }
}
