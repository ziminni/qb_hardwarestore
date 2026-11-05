import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/features/admin/viewmodels/admin_requisitions_viewmodel.dart';
import 'package:client/features/admin/widgets/admin_requisition_details_dialog.dart';
import 'package:client/features/admin/widgets/admin_requisition_token_panel.dart';
import 'package:client/features/admin/widgets/release_slip_document.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// The requisition approval queue, served to both shells that need it.
///
/// POS did **not** originate these rows: CPMS creates and submits them. That is why every row
/// carries its provenance (request number, project, that project's customer, the requesting
/// foreman) rather than just a number — a manager approving an anonymous list of material requests
/// is the failure mode the split creates.
///
/// One row carries its actions (D16: Approve and Reject both confirm first, and the approval's
/// confirmation names the goods and quantities because that list is what the manager is agreeing
/// to). Everything else about a requisition — its lines, what has been released, its release token
/// — lives in the row's detail, so the table stays one line per record at 1440 and 1100 px.
///
/// [viewmodel] is injectable so a test can observe what the screen sends. Production passes
/// nothing and the page owns its viewmodel.
class RequisitionsPage extends StatefulWidget {
  const RequisitionsPage({
    super.key,
    this.viewmodel,
    this.inSalesShell = false,
    this.slipPrinter,
  });

  final AdminRequisitionsViewmodel? viewmodel;

  /// Injected by tests; the app prints through [PdfReleaseSlipPrinter].
  final ReleaseSlipPrinter? slipPrinter;

  /// Draw inside the Store Manager's shell (sales sidebar, index 7) instead of
  /// the admin one. See `SalesRequisitionsPage`.
  final bool inSalesShell;

  @override
  State<RequisitionsPage> createState() => _RequisitionsPageState();
}

class _RequisitionsPageState extends State<RequisitionsPage> {
  late final AdminRequisitionsViewmodel _viewmodel =
      widget.viewmodel ?? AdminRequisitionsViewmodel();
  late final bool _ownsViewmodel = widget.viewmodel == null;

  /// The chip that filters nothing.
  static const String _anyChip = 'All';

  /// The statuses the queue offers, waiting first: what needs a decision is the
  /// reason anybody opens this screen.
  static const List<RequisitionStatus> _chipStatuses = [
    RequisitionStatus.submitted,
    RequisitionStatus.approved,
    RequisitionStatus.released,
    RequisitionStatus.rejected,
  ];

  String _query = '';

  /// Null when every status is shown.
  RequisitionStatus? _status;

  bool get _isFiltered => _query.trim().isNotEmpty || _status != null;

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
    final body = AnimatedBuilder(
      animation: _viewmodel,
      builder: (context, _) => _body(context),
    );
    const subtitle = 'Review material requests and their current status.';
    if (widget.inSalesShell) {
      return SalesSkeletonLayout(
        title: 'Approvals',
        subtitle: subtitle,
        selectedNavigationIndex: SalesSkeletonLayout.approvalsIndex,
        onNavigationSelected: (index) => navigateSales(context, index),
        // The queue owns its scrolling: a long list builds only the rows on
        // screen instead of every card at once.
        scrollable: false,
        child: body,
      );
    }
    return AdminSkeletonLayout(
      title: 'Requisitions',
      subtitle: subtitle,
      selectedNavigationIndex: AdminSkeletonLayout.requisitionsIndex,
      scrollable: false,
      child: body,
    );
  }

  /// Approves in two steps: the confirmation names the goods, then the call is
  /// sent, then the token the approval minted is handed over at once.
  Future<void> _approve(Requisition row) async {
    if (!await _confirmApprove(row)) return;
    final approved = await _viewmodel.approve(row.id);
    if (!approved || !mounted) return;
    Requisition? match;
    for (final current in _viewmodel.requisitions) {
      if (current.id == row.id) match = current;
    }
    final approvedRow = match;
    final token = approvedRow?.token;
    if (approvedRow == null || token == null) return;
    await showApprovedTokenDialog(
      context,
      reqNumber: row.reqNumber,
      token: token,
      onPrintSlip: (slipContext) => _printSlip(slipContext, approvedRow),
    );
  }

  Future<void> _printSlip(BuildContext slipContext, Requisition row) =>
      printReleaseSlip(slipContext, row, printer: widget.slipPrinter);

  /// Rejects in two steps too, but the confirmation names no reason: the
  /// endpoint takes none (checked 2026-10-30, `apps/requisitions/views.py:224`).
  Future<void> _reject(Requisition row) async {
    if (!await _confirmReject(row)) return;
    await _viewmodel.reject(row.id);
  }

  /// D16: what is being approved, named line by line. A manager who cannot see
  /// the goods is agreeing to a number.
  Future<bool> _confirmApprove(Requisition row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Approve ${row.reqNumber}?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Approving mints the release token. The cashier needs it to '
                'release these goods, so hand it to the foreman.',
              ),
              const SizedBox(height: AppSpacing.md),
              for (final item in row.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    '${formatQuantity(item.quantity)} × ${item.variantName}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              if (row.items.isEmpty)
                const Text(
                  'No item lines on this requisition.',
                  style: TextStyle(fontSize: 14, color: AppColors.textPrimary),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep waiting'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<bool> _confirmReject(Requisition row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Reject ${row.reqNumber}?'),
        content: const Text(
          'The requisition is closed and the foreman has to submit a new one. '
          'It cannot be approved after this.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep waiting'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _showDetails(Requisition row) =>
      showAdminRequisitionDetails(context, row: row, onPrintSlip: _printSlip);

  Widget _body(BuildContext context) {
    final viewmodel = _viewmodel;
    final all = viewmodel.requisitions;
    final visible = _visibleRows(all);
    final hasRows = all.isNotEmpty;

    // A failed first load is ONE failure: the banner below replaces the table
    // rather than sitting above an empty state that reads as "nothing waiting".
    final loadFailure = viewmodel.loadError;
    final actionError = viewmodel.actionError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterBar(
          searchHint: 'Request number, project, or requester',
          onSearchChanged: (value) => setState(() => _query = value),
          options: _chipLabels(all),
          selected: _selectedChip(all),
          onSelected: _selectChip,
        ),
        const SizedBox(height: AppSpacing.lg),
        // The server's refusal of one action, kept apart from a failed read:
        // "that approval was refused" is not "we could not load the queue".
        if (actionError != null) ...[
          ErrorBanner(message: actionError),
          const SizedBox(height: AppSpacing.md),
        ],
        // A refresh that failed under rows already read: the rows are still
        // true, so the banner sits above them instead of replacing them.
        if (loadFailure != null && hasRows) ...[
          ErrorBanner(message: loadFailure, onRetry: viewmodel.load),
          const SizedBox(height: AppSpacing.md),
        ],
        Expanded(
          child: DataPanel<Requisition>(
            columns: _columns,
            rows: visible,
            emptyMessage: _isFiltered
                ? 'No requisitions match these filters.'
                : 'No material requisitions yet.',
            // Only the first read may replace the queue with a spinner, and
            // only while there is nothing to show yet.
            isLoading: viewmodel.isLoading && !hasRows,
            error: hasRows ? null : loadFailure,
            onRetry: viewmodel.load,
            onRowTap: _showDetails,
            rowKey: (row) => ValueKey('requisition-${row.id}'),
          ),
        ),
      ],
    );
  }

  List<DataPanelColumn<Requisition>> get _columns => [
    DataPanelColumn<Requisition>(
      label: 'Requisition',
      flex: 2,
      cell: (row) => Text(
        row.reqNumber,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    ),
    DataPanelColumn<Requisition>(
      label: 'Project',
      // The largest share: the project and its customer are the two facts
      // decision 09 requires on the row. Measured at 1100 px - a larger share
      // ellipsized the request number and wrapped the status badge instead.
      flex: 3,
      // Two lines in one cell: the project is what was asked for, the customer
      // is who eventually pays for it, and decision 09 requires both on the row.
      cell: (row) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.projectName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
          Text(
            row.projectCustomerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
    DataPanelColumn<Requisition>(
      label: 'Requested by',
      flex: 2,
      cell: (row) => Text(
        row.requestedByName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
      ),
    ),
    DataPanelColumn<Requisition>(label: 'Status', flex: 2, cell: _statusBadge),
    DataPanelColumn<Requisition>(label: 'Actions', flex: 3, cell: _actionsCell),
  ];

  /// The action on the row, offered only where the server would accept it. The
  /// viewmodel enforces the same rule; hiding it here too is what stops a
  /// manager pressing a button that can only fail. A row that already has a
  /// token gets one path to it, because handing it over is the approver's job.
  Widget _actionsCell(Requisition row) {
    if (row.status.isAwaitingApproval) {
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton(
            onPressed: _viewmodel.isLoading ? null : () => _approve(row),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Approve'),
          ),
          OutlinedButton(
            onPressed: _viewmodel.isLoading ? null : () => _reject(row),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Reject'),
          ),
        ],
      );
    }
    if (row.token != null) {
      return TextButton(
        onPressed: () => _showDetails(row),
        style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
        child: const Text('Token'),
      );
    }
    return const SizedBox.shrink();
  }

  /// Chip labels carry the live count ("Approved (2)"), so the chip a manager
  /// taps is also the answer to "how many".
  List<String> _chipLabels(List<Requisition> rows) => [
    _anyChip,
    for (final status in _chipStatuses)
      '${status.label} (${_countOf(rows, status)})',
  ];

  String _selectedChip(List<Requisition> rows) {
    final status = _status;
    return status == null
        ? _anyChip
        : '${status.label} (${_countOf(rows, status)})';
  }

  int _countOf(List<Requisition> rows, RequisitionStatus status) =>
      rows.where((row) => row.status == status).length;

  void _selectChip(String chip) {
    if (chip == _anyChip) {
      setState(() => _status = null);
      return;
    }
    // The count is part of the label and changes with the data; the status is
    // the part before it.
    final label = chip.replaceFirst(RegExp(r' \(\d+\)$'), '');
    for (final status in _chipStatuses) {
      if (status.label == label) {
        setState(() => _status = status);
        return;
      }
    }
  }

  /// The shared pill: the label is the message, the tone is only the hint.
  /// Waiting on a person is a warning, approved is work in progress, released
  /// is the success, and a rejection is the one outcome that needs explaining.
  static Widget _statusBadge(Requisition row) => StatusBadge(
    // A status this client was not taught shows the server's own word: a row is
    // never described as something we guessed.
    label:
        row.status == RequisitionStatus.unknown &&
            row.rawStatus.trim().isNotEmpty
        ? row.rawStatus.trim()
        : row.status.label,
    tone: switch (row.status) {
      RequisitionStatus.submitted => StatusTone.warning,
      RequisitionStatus.approved => StatusTone.info,
      RequisitionStatus.released => StatusTone.success,
      RequisitionStatus.rejected => StatusTone.error,
      RequisitionStatus.draft ||
      RequisitionStatus.unknown => StatusTone.neutral,
    },
  );

  /// Waiting first, then the rest in the server's order: the queue's job is
  /// what still needs a decision.
  List<Requisition> _visibleRows(List<Requisition> rows) {
    final visible = [
      for (final row in rows)
        if (_matches(row)) row,
    ];
    return [
      ...visible.where((row) => row.status.isAwaitingApproval),
      ...visible.where((row) => !row.status.isAwaitingApproval),
    ];
  }

  bool _matches(Requisition row) {
    final status = _status;
    if (status != null && row.status != status) return false;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [
      row.reqNumber,
      row.projectName,
      row.projectCustomerName,
      row.requestedByName,
      for (final item in row.items) item.variantName,
    ].join(' ').toLowerCase();
    return haystack.contains(query);
  }
}
