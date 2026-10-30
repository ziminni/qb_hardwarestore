import 'package:client/shared/widgets/metric_card.dart';
import 'package:flutter/material.dart';

class AdminUserMetricCard extends StatelessWidget {
  const AdminUserMetricCard({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MetricCard(label: label, value: value);
  }
}
