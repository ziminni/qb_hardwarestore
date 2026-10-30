import 'package:client/shared/widgets/metric_card.dart';
import 'package:flutter/material.dart';

class AdminInventorySummary extends StatelessWidget {
  const AdminInventorySummary({super.key, required this.metrics});

  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: metrics
          .map(
            (metric) => SizedBox(
              width: 190,
              child: MetricCard(label: metric.$1, value: metric.$2),
            ),
          )
          .toList(),
    );
  }
}
