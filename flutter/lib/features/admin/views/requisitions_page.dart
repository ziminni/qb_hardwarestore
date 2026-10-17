import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/features/admin/viewmodels/admin_requisitions_viewmodel.dart';
import 'package:flutter/material.dart';

/// The Store Manager's requisition queue — the POS half of decision 09.
///
/// POS did **not** originate these rows: CPMS creates and submits them. That is why every row
/// carries its provenance (request number, project, that project's customer, the requesting
/// foreman) rather than just a number — a manager approving an anonymous list of material requests
/// is the failure mode the split creates.
///
/// [viewmodel] is injectable so a test can observe what the screen sends. Production passes
/// nothing and the page owns its viewmodel.
class RequisitionsPage extends StatefulWidget {
  const RequisitionsPage({super.key, this.viewmodel});

  final AdminRequisitionsViewmodel? viewmodel;

  @override
  State<RequisitionsPage> createState() => _RequisitionsPageState();
}

class _RequisitionsPageState extends State<RequisitionsPage> {
  late final AdminRequisitionsViewmodel _viewmodel =
      widget.viewmodel ?? AdminRequisitionsViewmodel();
  late final bool _ownsViewmodel = widget.viewmodel == null;

  @override
  void initState() {
    super.initState();
    _viewmodel.load();
  }

  @override
  void dispose() {
    if (_ownsViewmodel) _viewmodel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminSkeletonLayout(
      title: 'Requisitions',
      subtitle: 'Review material requests and their current status.',
      selectedNavigationIndex: 4,
      child: AnimatedBuilder(
        animation: _viewmodel,
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final viewmodel = _viewmodel;

    if (viewmodel.isLoading && viewmodel.requisitions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    // A failed load is NOT an empty queue: "nothing is awaiting approval" and "we could not read
    // the list" must never look the same to the person deciding whether to chase a delivery.
    final error = viewmodel.loadError;
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: viewmodel.load, child: const Text('Retry')),
        ],
      );
    }

    final actionError = viewmodel.actionError;
    final rows = viewmodel.requisitions;
    if (rows.isEmpty) {
      return const Text('No material requisitions yet.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (actionError != null) ...[
          Text(
            actionError,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        for (final row in rows)
          _RequisitionRow(
            row: row,
            onApprove: () => viewmodel.approve(row.id),
            onReject: () => viewmodel.reject(row.id),
          ),
      ],
    );
  }
}

class _RequisitionRow extends StatelessWidget {
  const _RequisitionRow({
    required this.row,
    required this.onApprove,
    required this.onReject,
  });

  final Requisition row;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    // The action is offered only where the server would accept it. The viewmodel enforces the same
    // rule; hiding it here too is what stops a manager pressing a button that can only fail.
    final actionable = row.status.isAwaitingApproval;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  row.reqNumber,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Chip(label: Text(row.status.label)),
              ],
            ),
            const SizedBox(height: 8),
            Text('${row.projectName} · ${row.projectCustomerName}'),
            Text('Requested by ${row.requestedByName}'),
            if (row.items.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final item in row.items)
                Text('${item.quantity} × ${item.variantName}'),
            ],
            if (actionable) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton(
                    onPressed: onApprove,
                    child: const Text('Approve'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onReject,
                    child: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
