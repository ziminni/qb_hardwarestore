import 'package:flutter/material.dart';

class AdminSalesChart extends StatelessWidget {
  const AdminSalesChart({
    super.key,
    required this.values,
    required this.labels,
  });

  final List<double> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final maximum = values.reduce((a, b) => a > b ? a : b);
    // A zero-gross week makes maximum 0 (0/0 = NaN) and a refund-heavy day
    // goes negative — both violate FractionallySizedBox's heightFactor >= 0
    // and red-screen the tab. Zero range renders flat; negatives clamp to it.
    final double range = maximum <= 0 ? 1.0 : maximum;
    return SizedBox(
      height: 280,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(values.length, (index) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: (values[index] / range).clamp(0.0, 1.0),
                        child: const ColoredBox(color: Colors.black26),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(labels[index]),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
