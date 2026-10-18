import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_dashboard_metric_card.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:client/features/sales/widgets/sales_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The receivables screen, on real data.
///
/// Phase 4 task 7: this page read a mock list out of `SalesModuleViewmodel` until decision 14
/// opened `/api/v1/ledgers/` to the client. It now shows every open receivable the server
/// holds, and its three states (loading, failed, empty) are deliberately distinct - a failed
/// load must not look like a store that is owed nothing.
class SalesReceivablesPage extends StatelessWidget {
  const SalesReceivablesPage({super.key, this.viewmodel});

  /// Injected by tests so a state can be rendered WITHOUT a server.
  ///
  /// The page otherwise builds its own viewmodel, which means a widget test cannot put it into a
  /// failed-load state at all - and the failed-load rule (an em dash rather than P0.00, because a
  /// number beside an error banner states "this store is owed nothing") was verified only by
  /// reading. Same shape as the repository injection this codebase already uses in four places.
  final SalesReceivablesViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => (viewmodel ?? SalesReceivablesViewmodel())..load(),
      child: const _ReceivablesView(),
    );
  }
}

class _ReceivablesView extends StatelessWidget {
  const _ReceivablesView();

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<SalesReceivablesViewmodel>();
    final now = DateTime.now();
    // A failed load must not render money. Showing "Outstanding P0.00 / 0 open invoices" beside
    // an error banner states "this store is owed nothing" - the same dangerous claim the empty
    // message is worded to avoid, and a number is more believable than a caption.
    final totalsUnknown = viewmodel.loadError != null && !viewmodel.hasEntries;

    return SalesSkeletonLayout(
      title: 'Receivables',
      subtitle: 'Track unpaid, partial, and overdue customer balances.',
      selectedNavigationIndex: 4,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: 260,
                child: SalesDashboardMetricCard(
                  label: 'Outstanding',
                  value: totalsUnknown
                      ? '—'
                      : '₱${viewmodel.outstanding.toStringAsFixed(2)}',
                  caption: totalsUnknown
                      ? 'Not loaded'
                      : '${viewmodel.entries.length} open invoices',
                  icon: Icons.account_balance_wallet_outlined,
                  color: AppColors.info,
                ),
              ),
              SizedBox(
                width: 260,
                child: SalesDashboardMetricCard(
                  label: 'Overdue',
                  value: totalsUnknown
                      ? '—'
                      : '₱${viewmodel.overdue.toStringAsFixed(2)}',
                  caption: 'Requires follow-up',
                  icon: Icons.warning_amber_outlined,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (viewmodel.isLoading && !viewmodel.hasEntries)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (viewmodel.loadError != null) ...[
              _ErrorBanner(
                message: viewmodel.loadError!,
                onRetry: () => context.read<SalesReceivablesViewmodel>().load(),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            SalesRecordsTable(
              columns: const [
                'Invoice',
                'Customer',
                'Due Date',
                'Total',
                'Paid',
                'Balance',
                'Status',
                'Action',
              ],
              emptyMessage: viewmodel.loadError != null
                  // Not "no receivables": this screen failed to find out.
                  ? 'Receivables could not be loaded.'
                  : 'No receivables available.',
              rows: viewmodel.entries
                  .map((entry) => _row(context, entry, now))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _row(BuildContext context, LedgerEntry entry, DateTime now) {
    final status = entry.statusAt(now);
    return <Widget>[
      Text(entry.transactionNo),
      Text(entry.customerName),
      Text('${entry.dueDate.month}/${entry.dueDate.day}/${entry.dueDate.year}'),
      Text('₱${entry.originalAmount.toStringAsFixed(2)}'),
      Text('₱${entry.paidAmount.toStringAsFixed(2)}'),
      Text('₱${entry.balanceDue.toStringAsFixed(2)}'),
      SalesStatusBadge(label: status.label, tone: status.tone),
      // Decision 19: POST /ledger-payments/ is IsPOSOrReadOnly, so a Cashier may post —
      // the old "Admin-only" claim confused ledger-entry writes (staff-only) with payment
      // writes. The button posts through the viewmodel and stays disabled only in flight.
      Builder(
        builder: (rowContext) {
          final rowViewmodel = rowContext.read<SalesReceivablesViewmodel>();
          final paying = rowViewmodel.isPaying(entry.id);
          return TextButton(
            // The dialog route builds ABOVE this page's provider, so the viewmodel
            // travels as a constructor argument — a dialog-local context.read would
            // throw ProviderNotFoundException instead of opening anything.
            onPressed: paying
                ? null
                : () => _openPaymentDialog(rowContext, rowViewmodel, entry),
            child: paying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Record payment'),
          );
        },
      ),
    ];
  }
}

Future<void> _openPaymentDialog(
  BuildContext context,
  SalesReceivablesViewmodel viewmodel,
  LedgerEntry entry,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _RecordPaymentDialog(viewmodel: viewmodel, entry: entry),
  );
}

/// Amount entry for one receivable. Prefilled with the full balance; the cashier may
/// lower it for a partial payment. Over-amounts are refused before anything posts.
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

  @override
  Widget build(BuildContext context) {
    // Reads widget.viewmodel, never context: this route sits above the page's
    // provider and has no provider ancestor of its own.
    final viewmodel = widget.viewmodel;
    return AlertDialog(
      title: Text('Record payment — ${widget.entry.transactionNo}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (₱)'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _posting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _posting
              ? null
              : () async {
                  final parsed = double.tryParse(_amount.text.trim());
                  if (parsed == null) {
                    setState(() => _error = 'Enter a valid amount.');
                    return;
                  }
                  // Captured before the await: the lint forbids carrying a
                  // BuildContext across the async gap on a State.mounted guard.
                  final navigator = Navigator.of(context);
                  setState(() {
                    _posting = true;
                    _error = null;
                  });
                  final ok = await viewmodel.recordPayment(
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
                        viewmodel.payError ?? 'The payment could not be recorded.';
                  });
                },
          child: const Text('Record'),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
