import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:flutter/material.dart';

class SalesRecordsTable extends StatelessWidget {
  const SalesRecordsTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.emptyMessage,
  });
  final List<String> columns;
  final List<List<Widget>> rows;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(AppRadii.medium),
    ),
    clipBehavior: Clip.antiAlias,
    child: rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.all(48),
            child: Center(child: Text(emptyMessage)),
          )
        : SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStatePropertyAll(
                Theme.of(context).colorScheme.secondaryContainer,
              ),
              columns: columns
                  .map((column) => DataColumn(label: Text(column)))
                  .toList(),
              rows: rows
                  .map((row) => DataRow(cells: row.map(DataCell.new).toList()))
                  .toList(),
            ),
          ),
  );
}
