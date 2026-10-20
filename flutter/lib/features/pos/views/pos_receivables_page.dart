import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_dashboard_metric_card.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:client/features/sales/widgets/sales_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// POS-native receivables (tab 3). Reuses [SalesReceivablesViewmodel] — same
/// data and Record-payment action as the sales receivables page, wrapped in
/// the POS shell. See decisions 03, 04, and 19.
class PosReceivablesPage extends StatelessWidget {
  const PosReceivablesPage({super.key, this.viewmodel});

  final SalesReceivablesViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => (viewmodel ?? SalesReceivablesViewmodel())..load(),
      child: const _PosReceivablesView(),
    );
  }
}

class _PosReceivablesView extends StatelessWidget {
  const _PosReceivablesView();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SalesReceivablesViewmodel>();
    final now = DateTime.now();
    final totalsUnknown = vm.loadError != null && !vm.hasEntries;

    return DashboardShell(
      title: 'Record Payment',
      subtitle: 'Track unpaid balances and record customer payments.',
      selectedNavigationIndex: 3,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
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
                      : '₱${vm.outstanding.toStringAsFixed(2)}',
                  caption: totalsUnknown
                      ? 'Not loaded'
                      : '${vm.entries.length} open invoices',
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
                      : '₱${vm.overdue.toStringAsFixed(2)}',
                  caption: 'Requires follow-up',
                  icon: Icons.warning_amber_outlined,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (vm.isLoading && !vm.hasEntries)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            if (vm.loadError != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppSpacing.sm),
                  border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: AppColors.error),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(vm.loadError!)),
                    TextButton(
                      onPressed: () =>
                          context.read<SalesReceivablesViewmodel>().load(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
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
              emptyMessage: vm.loadError != null
                  ? 'Receivables could not be loaded.'
                  : 'No receivables available.',
              rows: vm.entries
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
      Builder(
        builder: (rowContext) {
          final rowVm = rowContext.read<SalesReceivablesViewmodel>();
          final paying = rowVm.isPaying(entry.id);
          return TextButton(
            onPressed: paying
                ? null
                : () => _openPaymentDialog(rowContext, rowVm, entry),
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
                        widget.viewmodel.payError ??
                        'The payment could not be recorded.';
                  });
                },
          child: const Text('Record'),
        ),
      ],
    );
  }
}
