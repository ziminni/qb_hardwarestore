import 'package:flutter/material.dart';

class AdminRequisitionList extends StatelessWidget {
  const AdminRequisitionList({super.key, required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('REFERENCE')),
          DataColumn(label: Text('LOCATION')),
          DataColumn(label: Text('REQUESTED BY')),
          DataColumn(label: Text('CONTENTS')),
          DataColumn(label: Text('STATUS')),
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
