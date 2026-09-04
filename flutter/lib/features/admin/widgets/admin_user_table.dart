import 'package:flutter/material.dart';

class AdminUserTable extends StatelessWidget {
  const AdminUserTable({super.key});

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('[ Full name ]', '[ username ]', '[ email ]', '[ Admin ]', '[ Active ]'),
      (
        '[ Full name ]',
        '[ username ]',
        '[ email ]',
        '[ Inventory ]',
        '[ Active ]',
      ),
      ('[ Full name ]', '[ username ]', '[ email ]', '[ POS ]', '[ Inactive ]'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('NAME')),
          DataColumn(label: Text('USERNAME')),
          DataColumn(label: Text('EMAIL')),
          DataColumn(label: Text('ROLE')),
          DataColumn(label: Text('STATUS')),
          DataColumn(label: Text('ACTIONS')),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                DataCell(Text(row.$1)),
                DataCell(Text(row.$2)),
                DataCell(Text(row.$3)),
                DataCell(Text(row.$4)),
                DataCell(Text(row.$5)),
                DataCell(
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'View account',
                        onPressed: () {},
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Edit account',
                        onPressed: () {},
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'More actions',
                        onPressed: () {},
                        icon: const Icon(Icons.more_horiz, size: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
