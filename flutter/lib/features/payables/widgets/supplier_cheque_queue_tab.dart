import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/features/payables/viewmodels/payables_viewmodel.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The supplier cheque queue (Phase 8 F3, decision 20 #3), mirroring the
/// customer cheque queue: one status chip, the oldest cheque first, and the
/// single decision each cheque gets.
///
/// A supplier cheque already lowered the bill when it was issued — the money is
/// promised, not paid. So this queue only records what the bank did: `Cleared`
/// moves nothing, and `Bounced` puts the amount back on the bill server-side.
///
/// [canDecide] is the role gate, not a state: only a Store Manager or Admin may
/// decide (the server answers 403 to a Stock Manager), so the buttons are not
/// rendered for them.
class SupplierChequeQueueTab extends StatefulWidget {
  const SupplierChequeQueueTab({super.key, this.canDecide = false});

  final bool canDecide;

  @override
  State<SupplierChequeQueueTab> createState() => _SupplierChequeQueueTabState();
}

class _SupplierChequeQueueTabState extends State<SupplierChequeQueueTab> {
  static const String _anyStatus = 'All';

  String _query = '';

  @override
  void initState() {
    super.initState();
    // Read once, when the tab is first opened.
    context.read<PayablesViewmodel>().ensureCheques();
  }

  /// The chip rows, then the search text. Both narrow what is already loaded:
  /// the server answered with the cheques, not one page of them.
  List<SupplierPayment> _visibleRows(PayablesViewmodel state) {
    final query = _query.trim().toLowerCase();
    return [
      for (final cheque in state.filteredCheques)
        if (query.isEmpty ||
            '${cheque.chequeNumber} ${cheque.chequeBank} '
                    'Bill #${cheque.billId}'
                .toLowerCase()
                .contains(query))
          cheque,
    ];
  }

  /// The status a chip names, or null for the "All" chip.
  SupplierPaymentStatus? _statusFor(String chip) {
    for (final status in SupplierPaymentStatus.values) {
      if (status.label == chip) return status;
    }
    return null;
  }

  /// "Nothing waiting" and "these filters hide everything" are different facts.
  String _emptyMessage(PayablesViewmodel state) =>
      _query.trim().isNotEmpty || state.chequeStatusFilter != null
      ? 'No supplier cheques match these filters.'
      : 'No supplier cheques yet. A cheque is recorded as a payment against a '
            'bill.';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PayablesViewmodel>();
    final rows = _visibleRows(state);
    final firstLoadFailed = state.chequesError != null && state.cheques.isEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterBar(
            searchHint: 'Cheque no., bank or bill',
            onSearchChanged: (value) => setState(() => _query = value),
            options: [
              _anyStatus,
              for (final status in SupplierPaymentStatus.values) status.label,
            ],
            selected: state.chequeStatusFilter?.label ?? _anyStatus,
            onSelected: (chip) => state.setChequeStatusFilter(_statusFor(chip)),
          ),
          if (state.chequesError != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(
              message: state.chequesError!,
              onRetry: state.ensureCheques,
            ),
          ],
          // A refused decision says what the server said: it is never softened
          // into "the cheque could not be saved".
          if (state.decisionError != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: state.decisionError!),
          ],
          const SizedBox(height: AppSpacing.md),
          // No Expanded: this tab is one section of the page's scrolling list
          // (the same reason the page has no TabBarView). The panel pages its
          // own rows, so a long queue costs one page of widgets, not all of it.
          if (!firstLoadFailed)
            DataPanel<SupplierPayment>(
              rows: rows,
              isLoading: state.isLoadingCheques && state.cheques.isEmpty,
              emptyMessage: _emptyMessage(state),
              rowKey: (cheque) => ValueKey('payables-cheque.${cheque.id}'),
              columns: _columns(state),
            ),
        ],
      ),
    );
  }

  List<DataPanelColumn<SupplierPayment>> _columns(PayablesViewmodel state) => [
    DataPanelColumn<SupplierPayment>(
      label: 'Cheque',
      flex: 3,
      cell: (cheque) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(
            '${cheque.chequeNumber ?? 'No number'} · '
            '${cheque.chequeBank ?? 'No bank'}',
          ),
          const SizedBox(height: 2),
          _caption('Bill #${cheque.billId}'),
        ],
      ),
    ),
    DataPanelColumn<SupplierPayment>(
      label: 'Cheque date',
      flex: 2,
      cell: (cheque) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(
            cheque.chequeDate == null
                ? 'No date on file'
                : formatDate(cheque.chequeDate!),
          ),
          if (cheque.paidOn != null)
            _caption('Issued ${formatDate(cheque.paidOn!)}'),
        ],
      ),
    ),
    DataPanelColumn<SupplierPayment>(
      label: 'Amount',
      numeric: true,
      flex: 2,
      cell: (cheque) => _text(
        formatPeso(cheque.amount),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    DataPanelColumn<SupplierPayment>(
      label: 'Status',
      flex: 2,
      cell: (cheque) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(label: cheque.statusLabel, tone: _tone(cheque.status)),
          if (cheque.decisionReason.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            // A bounced cheque's reason is what the next call to the supplier is
            // about, so it is never dropped.
            _caption(cheque.decisionReason),
          ],
          if (cheque.decidedByName case final name?) _caption('By $name'),
        ],
      ),
    ),
    DataPanelColumn<SupplierPayment>(
      label: 'Action',
      flex: 3,
      cell: (cheque) => _actions(state, cheque),
    ),
  ];

  Widget _actions(PayablesViewmodel state, SupplierPayment cheque) {
    // A decided cheque is history: the server refuses a second decision with
    // 409, so nothing is offered.
    if (!cheque.isIssued) {
      return _caption(
        cheque.decidedAt == null
            ? 'Decided'
            : 'Decided ${formatDate(cheque.decidedAt!)}',
      );
    }
    if (!widget.canDecide) {
      return _caption('Read only');
    }
    if (state.isDeciding(cheque.id)) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        TextButton(
          onPressed: () => _openClearDialog(context, state, cheque),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => _openBounceDialog(context, state, cheque),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Bounce'),
        ),
      ],
    );
  }

  StatusTone _tone(SupplierPaymentStatus? status) => switch (status) {
    SupplierPaymentStatus.issued => StatusTone.warning,
    SupplierPaymentStatus.cleared => StatusTone.success,
    SupplierPaymentStatus.bounced => StatusTone.error,
    null => StatusTone.neutral,
  };

  Widget _text(String value, {TextStyle? style}) => Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: style ?? const TextStyle(fontSize: 14),
  );

  Widget _caption(String value) => Text(
    value,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
  );
}

/// The viewmodel travels as an argument into these dialogs: the tab's provider
/// sits above this page, and a dialog's own context cannot see it.
Future<void> _openClearDialog(
  BuildContext context,
  PayablesViewmodel state,
  SupplierPayment cheque,
) => showDialog<void>(
  context: context,
  builder: (_) => _ClearSupplierChequeDialog(state: state, cheque: cheque),
);

Future<void> _openBounceDialog(
  BuildContext context,
  PayablesViewmodel state,
  SupplierPayment cheque,
) => showDialog<void>(
  context: context,
  builder: (_) => _BounceSupplierChequeDialog(state: state, cheque: cheque),
);

/// Confirmation for the decision that moves nothing: clearing confirms money the
/// bill already counted, so it says so rather than implying a new payment.
class _ClearSupplierChequeDialog extends StatefulWidget {
  const _ClearSupplierChequeDialog({required this.state, required this.cheque});

  final PayablesViewmodel state;
  final SupplierPayment cheque;

  @override
  State<_ClearSupplierChequeDialog> createState() =>
      _ClearSupplierChequeDialogState();
}

class _ClearSupplierChequeDialogState
    extends State<_ClearSupplierChequeDialog> {
  String? _error;
  bool _sending = false;

  Future<void> _submit() async {
    final navigator = Navigator.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    final ok = await widget.state.clearCheque(widget.cheque);
    if (!mounted) return;
    if (ok) {
      navigator.pop();
      return;
    }
    setState(() {
      _sending = false;
      _error =
          widget.state.decisionError ??
          'The cheque could not be cleared. Reload before deciding again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cheque = widget.cheque;
    final failure = _error;
    return AppDialog(
      icon: Icons.check_circle_outline,
      title: 'Clear cheque ${cheque.chequeNumber ?? 'without a number'}',
      subtitle: 'Bill #${cheque.billId}',
      width: 460,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailRow(label: 'Amount', value: formatPeso(cheque.amount)),
          DetailRow(label: 'Bank', value: cheque.chequeBank ?? 'No bank'),
          DetailRow(
            label: 'Cheque date',
            value: cheque.chequeDate == null
                ? 'No date on file'
                : formatDate(cheque.chequeDate!),
          ),
          const SizedBox(height: AppSpacing.lg),
          const InfoBanner(
            message:
                'The bill already counted this cheque when it was issued, so '
                'clearing moves no money. Only clear it once the bank has '
                'honoured it.',
          ),
          if (failure != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              failure,
              style: const TextStyle(fontSize: 13, color: AppColors.errorText),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sending ? null : _submit,
          child: Text(_sending ? 'Clearing' : 'Clear cheque'),
        ),
      ],
    );
  }
}

/// The bounce dialog. A reason is REQUIRED — the server answers
/// `CHEQUE_REASON_REQUIRED` — and the amount goes BACK on the bill, which the
/// dialog states before it happens.
class _BounceSupplierChequeDialog extends StatefulWidget {
  const _BounceSupplierChequeDialog({
    required this.state,
    required this.cheque,
  });

  final PayablesViewmodel state;
  final SupplierPayment cheque;

  @override
  State<_BounceSupplierChequeDialog> createState() =>
      _BounceSupplierChequeDialogState();
}

class _BounceSupplierChequeDialogState
    extends State<_BounceSupplierChequeDialog> {
  final _reason = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canSend => _reason.text.trim().isNotEmpty && !_sending;

  Future<void> _submit() async {
    if (!_canSend) return;
    final navigator = Navigator.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    final ok = await widget.state.bounceCheque(
      widget.cheque,
      _reason.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      navigator.pop();
      return;
    }
    setState(() {
      _sending = false;
      _error =
          widget.state.decisionError ??
          'The cheque could not be bounced. Reload before deciding again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cheque = widget.cheque;
    final failure = _error;
    return AppDialog(
      icon: Icons.assignment_return_outlined,
      title: 'Bounce cheque ${cheque.chequeNumber ?? 'without a number'}',
      subtitle: 'Bill #${cheque.billId}',
      width: 460,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailRow(label: 'Amount', value: formatPeso(cheque.amount)),
          DetailRow(label: 'Bank', value: cheque.chequeBank ?? 'No bank'),
          const SizedBox(height: AppSpacing.lg),
          InfoBanner(
            message:
                '${formatPeso(cheque.amount)} goes back onto the bill. Bouncing '
                'closes this cheque; it does not cancel what the shop owes.',
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLines: 2,
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() => _error = null),
            decoration: const InputDecoration(
              labelText: 'Why did the bank refuse it?',
              hintText: 'Insufficient funds, closed account, stale date',
              isDense: true,
            ),
          ),
          if (failure != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              failure,
              style: const TextStyle(fontSize: 13, color: AppColors.errorText),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSend ? _submit : null,
          child: Text(_sending ? 'Saving' : 'Mark bounced'),
        ),
      ],
    );
  }
}
