import 'package:client/data/models/user.dart';
import 'package:flutter/material.dart';

class AdminUserTable extends StatelessWidget {
  const AdminUserTable({super.key, required this.users});

  final List<User> users;

  @override
  Widget build(BuildContext context) {
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
          for (final user in users)
            DataRow(
              cells: [
                DataCell(Text(user.fullName)),
                DataCell(Text(user.username)),
                DataCell(Text(user.email)),
                DataCell(Text(user.role.displayName)),
                DataCell(Text(user.isActive ? 'Active' : 'Inactive')),
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
