import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/features/admin/viewmodels/admin_mock_data.dart';
import 'package:client/features/admin/widgets/admin_audit_log_table.dart';
import 'package:flutter/material.dart';

class AuditLogsPage extends StatelessWidget {
  const AuditLogsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminSkeletonLayout(
      title: 'Audit Logs',
      subtitle: 'Review recorded activity across the system.',
      selectedNavigationIndex: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System activity',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          AdminAuditLogTable(rows: AdminMockData.auditLogs),
        ],
      ),
    );
  }
}
