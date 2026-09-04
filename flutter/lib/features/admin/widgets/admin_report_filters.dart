import 'package:flutter/material.dart';

class AdminReportFilters extends StatelessWidget {
  const AdminReportFilters({super.key, required this.reportTypes});

  final List<String> reportTypes;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<String>(
            initialValue: reportTypes.first,
            decoration: const InputDecoration(
              labelText: 'Report type',
              border: OutlineInputBorder(),
            ),
            items: reportTypes
                .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                .toList(),
            onChanged: (_) {},
          ),
        ),
        const SizedBox(
          width: 220,
          child: TextField(
            decoration: InputDecoration(
              labelText: 'Date range',
              hintText: 'Select dates',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.bar_chart),
          label: const Text('Generate'),
        ),
      ],
    );
  }
}
