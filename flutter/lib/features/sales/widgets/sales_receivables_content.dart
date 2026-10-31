import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The one receivables list, shared by the cashier's Record payment screen and
/// the Store Manager's Receivables screen (card S2).
///
/// Both screens used to be built twice from the same viewmodel with different
/// features: the manager had status chips and no error box, the cashier had a
/// hand-built red box and no filters, and both hid "Record payment" in the
/// eighth column of a table that scrolled sideways under 1100 px. This widget
/// is the whole screen body for both, so the two can no longer disagree.
///
/// It owns presentation state only (the search text); the status chip drives
/// [SalesReceivablesViewmodel.setStatusFilter], the same source the rows and the
/// tiles read. Every number comes from the viewmodel, none is invented here.
///
/// The page must give it a bounded slot (`scrollable: false` on the role shell):
/// the panel then scrolls its own rows and builds only the visible ones.
class SalesReceivablesContent extends StatefulWidget {
  const SalesReceivablesContent({super.key});

  @override
  State<SalesReceivablesContent> createState() =>
      _SalesReceivablesContentState();
}

class _SalesReceivablesContentState extends State<SalesReceivablesContent> {
  /// The chip that filters nothing.
  static const String _anyStatus = 'All';

  /// The chip labels are the status labels the badges use, so a chip and a row
  /// badge cannot describe the same debt with two different words.
  static final List<String> _statusChips = [
    _anyStatus,
    for (final status in LedgerStatus.values) status.label,
  ];

  /// What the tiles say when the load failed: a peso amount beside an error
  /// banner would claim "this store is owed nothing", which is exactly the
  /// claim a failed load cannot make.
  static const String _notLoaded = 'Not loaded';

  String _query = '';

  /// Rows the status chip left visible, then narrowed by the search text. The
  /// chip goes through the viewmodel so the tiles and the list stay one dataset.
  List<LedgerEntry> _visibleRows(SalesReceivablesViewmodel viewmodel) {
    final rows = viewmodel.filteredEntries;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return [
      for (final entry in rows)
        if ('${entry.customerName} ${entry.transactionNo}'
            .toLowerCase()
            .contains(query))
          entry,
    ];
  }

  LedgerStatus? _statusFor(String chip) {
    for (final status in LedgerStatus.values) {
      if (status.label == chip) return status;
    }
    return null;
  }

  /// "Nothing exists yet" and "these filters hide everything" are different
  /// facts, and a failed load is a third: it must never read as "nothing owed".
  String _emptyMessage(SalesReceivablesViewmodel viewmodel) {
    if (viewmodel.loadError != null) return 'Receivables could not be loaded.';
    if (_query.trim().isNotEmpty || viewmodel.statusFilter != null) {
      return 'No receivables match these filters.';
    }
    return 'No receivables available.';
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<SalesReceivablesViewmodel>();
    // Read once per build: a status computed from a moving clock could change
    // halfway down the list at midnight.
    final now = DateTime.now();
    final totalsUnknown = viewmodel.loadError != null && !viewmodel.hasEntries;
    final rows = _visibleRows(viewmodel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MetricGrid(
          children: [
            MetricTile(
              label: 'Outstanding',
              value: totalsUnknown
                  ? _notLoaded
                  : formatPeso(viewmodel.outstanding),
              caption: totalsUnknown
                  ? null
                  : '${formatCount(viewmodel.entries.length)} open invoices',
            ),
            MetricTile(
              label: 'Overdue',
              value: totalsUnknown ? _notLoaded : formatPeso(viewmodel.overdue),
              caption: totalsUnknown ? null : 'Requires follow-up',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        FilterBar(
          searchHint: 'Customer or invoice',
          onSearchChanged: (value) => setState(() => _query = value),
          options: _statusChips,
          selected: viewmodel.statusFilter?.label ?? _anyStatus,
          onSelected: (chip) => viewmodel.setStatusFilter(_statusFor(chip)),
        ),
        // A refresh that fails keeps the rows it already had, so the failure
        // needs to be said out loud above them.
        if (viewmodel.loadError case final failure?) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorBanner(message: failure, onRetry: viewmodel.load),
        ],
        const SizedBox(height: AppSpacing.lg),
        // The panel takes the height the page has left over, which is what lets
        // it scroll its own rows instead of building the whole ledger at once.
        Expanded(
          child: LayoutBuilder(
            builder: (context, slot) {
              // DataPanel turns the table into cards on its own content width.
              // Total and Paid only join as columns on a card: as two more table
              // columns they pushed the balance and the action off a 1100 px
              // window, which is the defect this screen is being rebuilt for.
              final cards =
                  slot.maxWidth - AppPanel.chrome < DataPanel.cardBreakpoint;
              return DataPanel<LedgerEntry>(
                columns: _columns(viewmodel, now, cards: cards),
                rows: rows,
                emptyMessage: _emptyMessage(viewmodel),
                // Rows already on screen outlive a refresh: the spinner is only
                // for a first load with nothing to show yet.
                isLoading: viewmodel.isLoading && viewmodel.entries.isEmpty,
                rowKey: (entry) => ValueKey(entry.id),
              );
            },
          ),
        ),
      ],
    );
  }

  List<DataPanelColumn<LedgerEntry>> _columns(
    SalesReceivablesViewmodel viewmodel,
    DateTime now, {
    required bool cards,
  }) {
    return [
      DataPanelColumn<LedgerEntry>(
        label: 'Customer',
        flex: 3,
        // The invoice number rides under the customer rather than in a column
        // of its own: it is how the same customer's debts are told apart, and a
        // fifth column cost the money column its last digits at 1100 px.
        cell: (entry) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(entry.customerName, maxLines: 2),
            const SizedBox(height: 2),
            _caption(entry.transactionNo),
          ],
        ),
      ),
      DataPanelColumn<LedgerEntry>(
        label: 'Due',
        flex: 2,
        cell: (entry) {
          final status = entry.statusAt(now);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _text(formatDate(entry.dueDate)),
              const SizedBox(height: AppSpacing.xs),
              StatusBadge(label: status.label, tone: _tone(status)),
            ],
          );
        },
      ),
      if (cards) ...[
        DataPanelColumn<LedgerEntry>(
          label: 'Total',
          numeric: true,
          flex: 2,
          cell: (entry) => _text(formatPeso(entry.originalAmount)),
        ),
        DataPanelColumn<LedgerEntry>(
          label: 'Paid',
          numeric: true,
          flex: 2,
          cell: (entry) => _text(formatPeso(entry.paidAmount)),
        ),
      ],
      DataPanelColumn<LedgerEntry>(
        label: 'Balance',
        numeric: true,
        flex: 3,
        // The number the reader came for: bold, right aligned, tabular.
        cell: (entry) => _text(
          formatPeso(entry.balanceDue),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      DataPanelColumn<LedgerEntry>(
        label: 'Action',
        flex: 2,
        cell: (entry) => _actionButton(viewmodel, entry),
      ),
    ];
  }

  Widget _actionButton(SalesReceivablesViewmodel viewmodel, LedgerEntry entry) {
    final paying = viewmodel.isPaying(entry.id);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        // Disabled in flight so a double tap cannot post twice; the viewmodel
        // holds the same guard for the dialog's own Record button.
        onPressed: paying
            ? null
            : () => _openPaymentDialog(context, viewmodel, entry),
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: paying
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Record payment'),
      ),
    );
  }

  StatusTone _tone(LedgerStatus status) => switch (status) {
    LedgerStatus.current => StatusTone.success,
    LedgerStatus.dueSoon => StatusTone.warning,
    LedgerStatus.overdue => StatusTone.error,
  };

  Widget _text(String value, {int maxLines = 1, TextStyle? style}) {
    return Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style:
          style ?? const TextStyle(fontSize: 14, color: AppColors.textPrimary),
    );
  }

  Widget _caption(String value) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }
}

Future<void> _openPaymentDialog(
  BuildContext context,
  SalesReceivablesViewmodel viewmodel,
  LedgerEntry entry,
) {
  // The dialog route builds ABOVE this page's provider, so the viewmodel
  // travels as a constructor argument: a dialog-local context.read would throw
  // ProviderNotFoundException instead of opening anything.
  return showDialog<void>(
    context: context,
    builder: (_) => _RecordPaymentDialog(viewmodel: viewmodel, entry: entry),
  );
}

/// Amount entry for one receivable: prefilled with the whole balance, which the
/// cashier may lower for a partial payment. The viewmodel refuses zero, negative
/// and over-balance amounts before anything posts, and the dialog stays open on
/// any refusal so the message and the amounts stay on screen together.
class _RecordPaymentDialog extends StatefulWidget {
  const _RecordPaymentDialog({required this.viewmodel, required this.entry});

  final SalesReceivablesViewmodel viewmodel;
  final LedgerEntry entry;

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.entry.balanceDue.toStringAsFixed(2),
  );
  String? _error;
  bool _posting = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final parsed = double.tryParse(_amount.text.trim());
    if (parsed == null) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    // Captured before the await: the lint forbids carrying a BuildContext
    // across the async gap on a State.mounted guard.
    final navigator = Navigator.of(context);
    setState(() {
      _posting = true;
      _error = null;
    });
    final ok = await widget.viewmodel.recordPayment(
      entry: widget.entry,
      amount: parsed,
    );
    if (!mounted) return;
    if (ok) {
      navigator.pop();
      return;
    }
    setState(() {
      _posting = false;
      _error =
          widget.viewmodel.payError ?? 'The payment could not be recorded.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final failure = _error;
    return AlertDialog(
      title: Text('Record payment · ${widget.entry.transactionNo}'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Balance ${formatPeso(widget.entry.balanceDue)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              // The till's money styling: large, tabular, the one field on the
              // dialog a hand actually types into.
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              decoration: const InputDecoration(
                labelText: 'Amount (₱)',
                isDense: true,
              ),
            ),
            if (failure != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                failure,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.errorText,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _posting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _posting ? null : _submit,
          child: const Text('Record'),
        ),
      ],
    );
  }
}
