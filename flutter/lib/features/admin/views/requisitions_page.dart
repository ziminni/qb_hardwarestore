import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/features/admin/viewmodels/admin_mock_data.dart';
import 'package:client/features/admin/widgets/admin_requisition_list.dart';
import 'package:flutter/material.dart';

class RequisitionsPage extends StatelessWidget {
  const RequisitionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminSkeletonLayout(
      title: 'Requisitions',
      subtitle: 'Review material requests and their current status.',
      selectedNavigationIndex: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Material requisitions',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          AdminRequisitionList(rows: AdminMockData.requisitions),
        ],
      ),
    );
  }
}
