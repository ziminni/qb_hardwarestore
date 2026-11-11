import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/cheque.dart';
import 'package:client/features/sales/viewmodels/cheque_queue_viewmodel.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Store Manager's cheque queue: the cheques the shop is still waiting on,
/// oldest first, with the one decision each of them gets (Phase 4 task F5).
///
/// A cashier TAKES a cheque at the till; deciding whether the bank honoured it
/// moves the customer's utang, so this body is only reached from the manager's
/// Receivables screen (the cashier's Record payment shell never renders it).
///
/// The page must give it a bounded slot (`scrollable: false` on the role shell):
/// the panel then scrolls its own rows and builds only the visible ones.
class ChequeQueueContent extends StatefulWidget {
  const ChequeQueueContent({super.key});

  @override
  State<ChequeQueueContent> createState() => _ChequeQueueContentState();
}

class _ChequeQueueContentState extends State<ChequeQueueContent> {
  /// The chip that filters nothing.
  static const String _anyStatus = 'All';

  static final List<String> _statusChips = [
    _anyStatus,
    for (final status in ChequeStatus.values) status.label,
  ];

  String _query = '';

  /// Rows the status chip left visible, then narrowed by the search text. The
  /// chip goes through the viewmodel so the pending count on the tab and the
  /// rows here stay one dataset.
  List<Cheque> _visibleRows(ChequeQueueViewmodel viewmodel) {
    final rows = viewmodel.filteredCheques;
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return [
      for (final cheque in rows)
        if ('${cheque.customerName} ${cheque.chequeNumber} '
                '${cheque.bank} ${cheque.transactionNo}'
            .toLowerCase()
            .contains(query))
          cheque,
    ];
  }

  ChequeStatus? _statusFor(String chip) {
    for (final status in ChequeStatus.values) {
      if (status.label == chip) return status;
    }
    return null;
  }

  /// "Nothing waiting" and "these filters hide everything" are different facts.
  /// A failed load is a third, and the banner says it, not this line.
  String _emptyMessage(ChequeQueueViewmodel viewmodel) {
    if (_query.trim().isNotEmpty || viewmodel.statusFilter != null) {
      return 'No cheques match these filters.';
    }
    return 'No cheques on file yet.';
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<ChequeQueueViewmodel>();
    final rows = _visibleRows(viewmodel);
    final loadFailure = viewmodel.loadError;
    final decisionFailure = viewmodel.decisionError;
    // A first load that failed is ONE banner, and nothing goes under it: an
    // empty-state card there would say "nothing to chase", which a failed read
    // has not established. Rows already read stay on screen, because they hold.
    final firstLoadFailed = loadFailure != null && !viewmodel.hasCheques;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterBar(
          searchHint: 'Customer, cheque no. or bank',
          onSearchChanged: (value) => setState(() => _query = value),
          options: _statusChips,
          selected: viewmodel.statusFilter?.label ?? _anyStatus,
          onSelected: (chip) => viewmodel.setStatusFilter(_statusFor(chip)),
        ),
        if (loadFailure != null) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorBanner(message: loadFailure, onRetry: viewmodel.load),
        ],
        // A refused decision says what the server said, above rows that are now
        // the server's truth (a conflict reloads them).
        if (decisionFailure != null) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorBanner(message: decisionFailure),
        ],
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: firstLoadFailed
              ? const SizedBox.shrink()
              : DataPanel<Cheque>(
                  columns: _columns(viewmodel),
                  rows: rows,
                  emptyMessage: _emptyMessage(viewmodel),
                  // Rows already on screen outlive a refresh: the spinner is
                  // only for a first load with nothing to show yet.
                  isLoading: viewmodel.isLoading && !viewmodel.hasCheques,
                  rowKey: (cheque) => ValueKey(cheque.id),
                ),
        ),
      ],
    );
  }

  List<DataPanelColumn<Cheque>> _columns(ChequeQueueViewmodel viewmodel) {
    return [
      DataPanelColumn<Cheque>(
        label: 'Customer',
        flex: 3,
        // The cheque number rides under the customer: it is how two cheques from
        // the same customer are told apart at the bank window.
        cell: (cheque) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(cheque.customerName, maxLines: 2),
            const SizedBox(height: 2),
            _caption('${cheque.chequeNumber} · ${cheque.bank}'),
            const SizedBox(height: 2),
            _caption(cheque.transactionNo),
          ],
        ),
      ),
      DataPanelColumn<Cheque>(
        label: 'Cheque date',
        flex: 2,
        // The date written on the cheque, with how long it has been waiting:
        // "when did this arrive" is the question the queue answers.
        cell: (cheque) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(formatDate(cheque.chequeDate)),
            if (cheque.isPending && cheque.receivedAt == null)
              _caption('Not received yet')
            else if (cheque.isPending)
              _caption('Waiting since ${formatDate(cheque.receivedAt!)}'),
          ],
        ),
      ),
      DataPanelColumn<Cheque>(
        label: 'Amount',
        numeric: true,
        flex: 3,
        cell: (cheque) => _text(
          formatPeso(cheque.amount),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      DataPanelColumn<Cheque>(
        label: 'Status',
        flex: 2,
        cell: (cheque) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusBadge(label: cheque.status.label, tone: _tone(cheque.status)),
            if (cheque.status != ChequeStatus.pending) ...[
              const SizedBox(height: AppSpacing.xs),
              // Who decided it, and the reason when there is one: a bounced
              // cheque's reason is what the next collection call is about.
              if (cheque.decisionReason case final reason?
                  when reason.trim().isNotEmpty)
                _caption(reason),
              if (cheque.decidedByName case final name?) _caption(name),
            ],
          ],
        ),
      ),
      DataPanelColumn<Cheque>(
        label: 'Action',
        flex: 3,
        cell: (cheque) => _actions(viewmodel, cheque),
      ),
    ];
  }

  Widget _actions(ChequeQueueViewmodel viewmodel, Cheque cheque) {
    if (!cheque.isPending) {
      return _caption(
        cheque.decidedAt == null
            ? 'Decided'
            : 'Decided ${formatDate(cheque.decidedAt!)}',
      );
    }
    final deciding = viewmodel.isDeciding(cheque.id);
    if (deciding) {
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
          // Disabled in flight so a double tap cannot decide twice; the
          // viewmodel holds the same guard for the dialog's own button.
          onPressed: () => _openClearDialog(context, viewmodel, cheque),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => _openBounceDialog(context, viewmodel, cheque),
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

  StatusTone _tone(ChequeStatus status) => switch (status) {
    ChequeStatus.pending => StatusTone.warning,
    ChequeStatus.cleared => StatusTone.success,
    ChequeStatus.bounced => StatusTone.error,
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
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }
}

/// Sent above this page's provider, so the viewmodel travels as an argument: a
/// dialog-local `context.read` would throw ProviderNotFoundException.
Future<void> _openClearDialog(
  BuildContext context,
  ChequeQueueViewmodel viewmodel,
  Cheque cheque,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ClearChequeDialog(viewmodel: viewmodel, cheque: cheque),
  );
}

Future<void> _openBounceDialog(
  BuildContext context,
  ChequeQueueViewmodel viewmodel,
  Cheque cheque,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _BounceChequeDialog(viewmodel: viewmodel, cheque: cheque),
  );
}

/// Confirmation for the one decision that moves money: clearing marks the
/// customer's utang paid, so it is stated in full before it happens.
class _ClearChequeDialog extends StatefulWidget {
  const _ClearChequeDialog({required this.viewmodel, required this.cheque});

  final ChequeQueueViewmodel viewmodel;
  final Cheque cheque;

  @override
  State<_ClearChequeDialog> createState() => _ClearChequeDialogState();
}

class _ClearChequeDialogState extends State<_ClearChequeDialog> {
  String? _error;
  bool _sending = false;

  Future<void> _submit() async {
    final navigator = Navigator.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    final ok = await widget.viewmodel.clear(widget.cheque);
    if (!mounted) return;
    if (ok) {
      navigator.pop();
      return;
    }
    setState(() {
      _sending = false;
      _error =
          widget.viewmodel.decisionError ??
          'The cheque could not be cleared. Reload before deciding again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cheque = widget.cheque;
    final failure = _error;
    return AppDialog(
      icon: Icons.check_circle_outline,
      title: 'Clear cheque ${cheque.chequeNumber}',
      subtitle: cheque.customerName,
      width: 460,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailRow(label: 'Amount', value: formatPeso(cheque.amount)),
          DetailRow(label: 'Bank', value: cheque.bank),
          DetailRow(label: 'Cheque date', value: formatDate(cheque.chequeDate)),
          DetailRow(label: 'Sale', value: cheque.transactionNo),
          const SizedBox(height: AppSpacing.lg),
          InfoBanner(
            title: 'This records money received',
            message:
                'Clearing marks ${formatPeso(cheque.amount)} paid against this '
                'customer\'s utang. Only clear it once the bank has honoured the '
                'cheque.',
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

/// The bounce dialog. A reason is REQUIRED: the debt stays on the customer's
/// ledger, so the trail has to say why the bank refused it.
class _BounceChequeDialog extends StatefulWidget {
  const _BounceChequeDialog({required this.viewmodel, required this.cheque});

  final ChequeQueueViewmodel viewmodel;
  final Cheque cheque;

  @override
  State<_BounceChequeDialog> createState() => _BounceChequeDialogState();
}

class _BounceChequeDialogState extends State<_BounceChequeDialog> {
  final TextEditingController _reason = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canSend => _reason.text.trim().isNotEmpty && !_sending;

  Future<void> _submit() async {
    if (!_canSend) {
      setState(
        () => _error =
            'A bounced cheque needs a reason. Write down why the bank refused it.',
      );
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    final ok = await widget.viewmodel.bounce(widget.cheque, _reason.text);
    if (!mounted) return;
    if (ok) {
      navigator.pop();
      return;
    }
    setState(() {
      _sending = false;
      _error =
          widget.viewmodel.decisionError ??
          'The cheque could not be bounced. Reload before deciding again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final cheque = widget.cheque;
    final failure = _error;
    return AppDialog(
      icon: Icons.assignment_return_outlined,
      title: 'Bounce cheque ${cheque.chequeNumber}',
      subtitle: cheque.customerName,
      width: 460,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailRow(label: 'Amount', value: formatPeso(cheque.amount)),
          DetailRow(label: 'Bank', value: cheque.bank),
          const SizedBox(height: AppSpacing.lg),
          InfoBanner(
            message:
                'The customer still owes ${formatPeso(cheque.amount)}. Bouncing '
                'closes this cheque; it does not write the debt off.',
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _reason,
            autofocus: true,
            maxLines: 2,
            // The field is the one thing to fill, so the confirm button follows
            // it: typing enables it, and Enter submits from the keyboard.
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
