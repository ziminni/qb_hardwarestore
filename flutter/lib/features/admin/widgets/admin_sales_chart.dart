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
                        heightFactor: values[index] / maximum,
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
