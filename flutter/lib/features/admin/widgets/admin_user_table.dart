import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
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
                DataCell(
                  user.role == null
                      ? const _NoRoleBadge()
                      : Text(user.roleLabel),
                ),
                DataCell(Text(user.isActive ? 'Active' : 'Inactive')),
              ],
            ),
        ],
      ),
    );
  }
}

/// The ROLE cell for an account with no group.
///
/// `GET /users/` really answers `role: null` for one (a superuser, or an
/// account whose group was removed). A blank cell reads as a rendering bug, and
/// hiding the row would hide the account an admin has to fix — so the cell says
/// what the state is, in the warning tone the rest of the app uses.
class _NoRoleBadge extends StatelessWidget {
  const _NoRoleBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        User.noRoleLabel,
        style: const TextStyle(
          color: AppColors.warning,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
