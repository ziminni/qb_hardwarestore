import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/features/requisitions/viewmodels/project_requests_viewmodel.dart';
import 'package:client/features/requisitions/widgets/project_request_review_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The statuses the queue offers, in chip order.
///
/// WAITING is the store's work; the rest is history, opened read-only. The
/// server filters on one status at a time and returns it oldest first, so the
/// queue never merges two questions into one list.
const List<RequisitionStatus> projectRequestStatuses = [
  RequisitionStatus.waiting,
  RequisitionStatus.accepted,
  RequisitionStatus.declined,
  RequisitionStatus.partial,
  RequisitionStatus.released,
  RequisitionStatus.closed,
];

/// The shared queue body: filters, the lazy row list, and the review dialog.
///
/// One body for both shells (decision 13). It reads the screen-scoped
/// [ProjectRequestsViewmodel]; every word a reviewer needs — including the
/// server's own refusal copy — comes from it.
class ProjectRequestsContent extends StatefulWidget {
  const ProjectRequestsContent({super.key});

  @override
  State<ProjectRequestsContent> createState() => _ProjectRequestsContentState();
}

class _ProjectRequestsContentState extends State<ProjectRequestsContent> {
  /// Narrows the rows ALREADY LOADED for the selected status, so typing costs no
  /// request. The badge is deliberately not filtered by it.
  String _query = '';

  List<Requisition> _visible(List<Requisition> rows) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return [
      for (final row in rows)
        if (_matches(row, query)) row,
    ];
  }

  bool _matches(Requisition row, String query) => [
    row.reqNumber,
    row.cpmsRequestId ?? '',
    row.projectName,
    row.projectCustomerName,
    row.requestedByName,
  ].any((value) => value.toLowerCase().contains(query));

  String _emptyMessage(RequisitionStatus status) {
    if (_query.trim().isNotEmpty) return 'No requests match this search.';
    if (status == RequisitionStatus.waiting) {
      return 'No requests are waiting for the store.';
    }
    return 'No requests in this status.';
  }

  Future<void> _open(Requisition row) async {
    final viewmodel = context.read<ProjectRequestsViewmodel>();
    final message = await showDialog<String>(
      context: context,
      // The dialog is mounted on the ROOT navigator, above this subtree's
      // provider, so it gets the same viewmodel explicitly. Without this the
      // dialog threw ProviderNotFound and no review could open at all.
      builder: (_) => ChangeNotifierProvider<ProjectRequestsViewmodel>.value(
        value: viewmodel,
        child: ProjectRequestReviewDialog(
          viewmodel: viewmodel,
          requisition: viewmodel.detailFor(row.id) ?? row,
        ),
      ),
    );
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<ProjectRequestsViewmodel>();
    final rows = _visible(viewmodel.requests);
    final failure = viewmodel.loadError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterBar(
          searchHint: 'Search request, project, contractor or requester',
          options: [for (final status in projectRequestStatuses) status.label],
          selected: viewmodel.status.label,
          onSearchChanged: (value) => setState(() => _query = value),
          onSelected: (label) {
            for (final status in projectRequestStatuses) {
              if (status.label == label) viewmodel.selectStatus(status);
            }
          },
        ),
        Row(
          children: [
            const Spacer(),
            TextButton(
              key: const Key('refresh-requests'),
              onPressed: viewmodel.isLoading ? null : viewmodel.load,
              child: const Text('Refresh'),
            ),
          ],
        ),
        // A reload over rows keeps them and says why above the list; a first
        // load that failed is the panel's single error state below instead.
        if (failure != null && rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: ErrorBanner(message: failure, onRetry: viewmodel.load),
          ),
        Expanded(
          child: DataPanel<Requisition>(
            columns: [
              DataPanelColumn(
                label: 'Request',
                flex: 2,
                cell: (row) => Text(
                  row.reqNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              DataPanelColumn(
                label: 'Project',
                flex: 3,
                cell: (row) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.projectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // The contractor is the project's customer, not a second
                    // project: a Store Manager recognises the firm faster than
                    // the site name.
                    Text(
                      row.projectCustomerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              DataPanelColumn(
                label: 'Requested by',
                flex: 2,
                cell: (row) => Text(
                  row.requestedByName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DataPanelColumn(
                label: 'Received',
                flex: 2,
                cell: (row) => Text(
                  row.createdAt == null ? '—' : formatDate(row.createdAt!),
                ),
              ),
              DataPanelColumn(
                label: 'Status',
                flex: 2,
                cell: (row) => StatusBadge(
                  label: row.status.label,
                  tone: statusToneFor(row.status),
                ),
              ),
              DataPanelColumn(
                label: 'Action',
                // At weight 1 "Review" split mid-word at 1100 px (QA).
                flex: 2,
                cell: (row) => Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _open(row),
                    child: Text(
                      row.status == RequisitionStatus.waiting
                          ? 'Review'
                          : 'View',
                    ),
                  ),
                ),
              ),
            ],
            rows: rows,
            rowKey: (row) => ValueKey('request-${row.id}'),
            onRowTap: _open,
            emptyMessage: _emptyMessage(viewmodel.status),
            // The spinner is for the first load only: a reload over rows must
            // not wipe them while the banner above reports the failure.
            isLoading: viewmodel.isLoading && viewmodel.requests.isEmpty,
            error: rows.isEmpty && failure != null ? failure : null,
            onRetry: viewmodel.load,
          ),
        ),
      ],
    );
  }
}
