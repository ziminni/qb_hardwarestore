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
              ],
            ),
        ],
      ),
    );
  }
}
