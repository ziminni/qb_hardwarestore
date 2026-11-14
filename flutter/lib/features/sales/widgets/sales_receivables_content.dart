import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/features/sales/viewmodels/cheque_queue_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/widgets/cheque_queue_content.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:client/core/time/app_clock.dart';
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
///
/// [showCheques] adds the Store Manager's Cheques tab (F5). It is off by default
/// because the cashier's Record payment shell shows this same body and must not
/// reach the decision queue: a cashier TAKES a cheque, a manager decides it.
class SalesReceivablesContent extends StatefulWidget {
  const SalesReceivablesContent({super.key, this.showCheques = false});

  /// True only on the manager's Receivables screen, which also provides a
  /// [ChequeQueueViewmodel] above this widget.
  final bool showCheques;

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

  /// Which tab the manager is reading. The ledger is the default: the debts are
  /// what the screen is opened for, cheques are what is waiting on the bank.
  bool _showCheques = false;

  /// Rows the status chip left visible, then narrowed by the search text. The
  /// chip goes through the viewmodel so the tiles and the list stay one dataset.
  List<LedgerEntry> _visibleRows(SalesReceivablesViewmodel viewmodel) {
    final rows = viewmodel.filteredEntries;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return [
      for (final entry in rows)
        if ('${entry.customerName} ${entry.transactionNo} ${entry.projectName ?? ''}'
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
  /// facts. A failed load is a third, and it is said by the banner, not here:
  /// an inbox icon under the banner reads as "nothing owed".
  String _emptyMessage(SalesReceivablesViewmodel viewmodel) {
    if (_query.trim().isNotEmpty || viewmodel.statusFilter != null) {
      return 'No receivables match these filters.';
    }
    return 'No receivables available.';
  }

  @override
  Widget build(BuildContext context) {
    // The Cheques tab is the manager's: its viewmodel is only provided by the
    // manager's page, and only read when the tab exists.
    final chequeViewmodel = widget.showCheques
        ? context.watch<ChequeQueueViewmodel>()
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (chequeViewmodel != null) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<bool>(
              segments: [
                const ButtonSegment(
                  value: false,
                  label: Text('Utang'),
                  icon: Icon(Icons.receipt_long_outlined),
                ),
                ButtonSegment(
                  value: true,
                  // The pending count ON the tab (F5): the one marker needed to
                  // see that money is waiting on the bank without opening it.
                  label: Text('Cheques (${chequeViewmodel.pendingCount})'),
                  icon: const Icon(Icons.account_balance_outlined),
                ),
              ],
              selected: {_showCheques},
              onSelectionChanged: (values) =>
                  setState(() => _showCheques = values.first),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (_showCheques && chequeViewmodel != null)
          const Expanded(child: ChequeQueueContent())
        else
          // The ledger body owns an Expanded panel, so it needs the bounded
          // height this Column would otherwise not give it.
          Expanded(child: _ledgerSection(context)),
      ],
    );
  }

  /// The utang ledger, unchanged: tiles, filters, rows and the payment dialog.
  Widget _ledgerSection(BuildContext context) {
    final viewmodel = context.watch<SalesReceivablesViewmodel>();
    // Read once per build: a status computed from a moving clock could change
    // halfway down the list at midnight.
    final now = appClock.now();
    final failure = viewmodel.loadError;
    final totalsUnknown = failure != null && !viewmodel.hasEntries;
    final rows = _visibleRows(viewmodel);
    // FX3: a first load that failed is ONE banner. Nothing goes under it: a
    // panel empty state there would state the store is owed nothing, which is
    // the one fact a failed read has not established. Rows already read stay
    // on screen under the banner, because they are still true.
    final firstLoadFailed = failure != null && viewmodel.entries.isEmpty;

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
          searchHint: 'Customer, invoice or project',
          onSearchChanged: (value) => setState(() => _query = value),
          options: _statusChips,
          selected: viewmodel.statusFilter?.label ?? _anyStatus,
          onSelected: (chip) => viewmodel.setStatusFilter(_statusFor(chip)),
        ),
        // A refresh that fails keeps the rows it already had, so the failure
        // needs to be said out loud above them.
        if (failure != null) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorBanner(message: failure, onRetry: viewmodel.load),
        ],
        const SizedBox(height: AppSpacing.lg),
        // The panel takes the height the page has left over, which is what lets
        // it scroll its own rows instead of building the whole ledger at once.
        Expanded(
          child: firstLoadFailed
              ? const SizedBox.shrink()
              : LayoutBuilder(
                  builder: (context, slot) {
                    // DataPanel turns the table into cards on its own content
                    // width. Total and Paid only join as columns on a card: as
                    // two more table columns they pushed the balance and the
                    // action off a 1100 px window, which is the defect this
                    // screen is being rebuilt for.
                    final cards =
                        slot.maxWidth - AppPanel.chrome <
                        DataPanel.cardBreakpoint;
                    return DataPanel<LedgerEntry>(
                      columns: _columns(viewmodel, now, cards: cards),
                      rows: rows,
                      emptyMessage: _emptyMessage(viewmodel),
                      // Rows already on screen outlive a refresh: the spinner
                      // is only for a first load with nothing to show yet.
                      isLoading:
                          viewmodel.isLoading && viewmodel.entries.isEmpty,
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
            // Decision 03: the contractor pays, the project is what the counter is
            // told, so it rides under the payer - the same caption the manager's
            // sales table uses for the source and the payment. A counter sale has
            // no project, and then the line is simply not there.
            if (entry.projectName case final project?) ...[
              const SizedBox(height: 2),
              _caption(project),
            ],
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
  final TextEditingController _chequeNumber = TextEditingController();
  final TextEditingController _bank = TextEditingController();
  DateTime? _chequeDate;
  bool _isCheque = false;
  String? _error;
  String? _notice;
  bool _posting = false;

  @override
  void dispose() {
    _amount.dispose();
    _chequeNumber.dispose();
    _bank.dispose();
    super.dispose();
  }

  /// The date written on the cheque. Keyboard and pointer both reach it: the
  /// field opens the date picker, and the picker takes typed dates too.
  Future<void> _pickChequeDate() async {
    final today = appClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _chequeDate ?? today,
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 2),
      helpText: 'Date on the cheque',
    );
    if (picked == null || !mounted) return;
    setState(() => _chequeDate = picked);
  }

  Future<void> _submit() async {
    final parsed = double.tryParse(_amount.text.trim());
    if (parsed == null) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    if (_isCheque && _chequeDate == null) {
      setState(() => _error = 'Pick the date written on the cheque.');
      return;
    }
    // Captured before the await: the lint forbids carrying a BuildContext
    // across the async gap on a State.mounted guard.
    final navigator = Navigator.of(context);
    setState(() {
      _posting = true;
      _error = null;
    });
    if (_isCheque) {
      final cheque = await widget.viewmodel.recordChequePayment(
        entry: widget.entry,
        amount: parsed,
        chequeNumber: _chequeNumber.text,
        bank: _bank.text,
        chequeDate: _chequeDate!,
      );
      if (!mounted) return;
      if (cheque != null) {
        // NOT "paid": the bank has not honoured it yet, so the dialog says what
        // actually happened and the balance on the row stays as it was.
        setState(() {
          _posting = false;
          _notice =
              'Cheque ${cheque.chequeNumber} is recorded as pending clearance. '
              'The ${formatPeso(widget.entry.balanceDue)} still stands until the '
              'bank honours it.';
        });
        return;
      }
      setState(() {
        _posting = false;
        _error = widget.viewmodel.payError ?? 'The cheque could not be recorded.';
      });
      return;
    }
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
    final notice = _notice;
    return AlertDialog(
      title: Text('Record payment \u00b7 ${widget.entry.transactionNo}'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.entry.customerName} owes '
              '${formatPeso(widget.entry.balanceDue)}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Cash')),
                ButtonSegment(
                  value: true,
                  label: Text('Cheque'),
                  icon: Icon(Icons.account_balance_outlined),
                ),
              ],
              selected: {_isCheque},
              // Locked once a cheque is on its way: switching the method
              // mid-post would post the other one.
              onSelectionChanged: _posting || notice != null
                  ? null
                  : (values) => setState(() {
                      _isCheque = values.first;
                      _error = null;
                    }),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amount,
              enabled: !_posting && notice == null,
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
                labelText: 'Amount (\u20b1)',
                isDense: true,
              ),
            ),
            if (_isCheque) ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _chequeNumber,
                enabled: !_posting && notice == null,
                decoration: const InputDecoration(
                  labelText: 'Cheque number',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _bank,
                enabled: !_posting && notice == null,
                decoration: const InputDecoration(
                  labelText: 'Bank',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _posting || notice != null ? null : _pickChequeDate,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  _chequeDate == null
                      ? 'Date on the cheque'
                      : formatDate(_chequeDate!),
                ),
              ),
            ],
            if (notice != null) ...[
              const SizedBox(height: AppSpacing.md),
              InfoBanner(title: 'Pending clearance', message: notice),
            ],
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
          child: Text(notice == null ? 'Cancel' : 'Close'),
        ),
        if (notice == null)
          FilledButton(
            onPressed: _posting ? null : _submit,
            child: Text(_isCheque ? 'Record cheque' : 'Record'),
          ),
      ],
    );
  }
}
