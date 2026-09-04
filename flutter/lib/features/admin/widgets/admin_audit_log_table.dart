import 'package:flutter/material.dart';

class AdminAuditLogTable extends StatelessWidget {
  const AdminAuditLogTable({super.key, required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('TIME')),
          DataColumn(label: Text('USER')),
          DataColumn(label: Text('ACTION')),
          DataColumn(label: Text('DESCRIPTION')),
        ],
        rows: rows
            .map(
              (row) => DataRow(
                cells: row.map((value) => DataCell(Text(value))).toList(),
              ),
            )
            .toList(),
      ),
    );
  }
}
