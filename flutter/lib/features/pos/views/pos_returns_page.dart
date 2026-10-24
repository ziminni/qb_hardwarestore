import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/pos_returns_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// The till's Returns tab (index 6, decision 05).
///
/// A customer comes back with goods and a slip. The cashier searches the sale,
/// the screen shows what is LEFT to return and what the sale still owes, and the
/// server decides the money: the return value settles the utang first and only
/// the excess leaves the drawer.
///
/// No open shift, no refund: a refund is cash out of a drawer, and a drawer is a
/// shift. The gate is the same one the till uses, and for the same reason — an
/// orphan refund makes the Z-reading's expected drawer too high.
///
/// [viewmodel] and [shiftViewmodel] are injectable so a test can drive the whole
/// flow without a server; production passes nothing.
class PosReturnsPage extends StatefulWidget {
  const PosReturnsPage({super.key, this.viewmodel, this.shiftViewmodel});

  final PosReturnsViewmodel? viewmodel;
  final ShiftViewmodel? shiftViewmodel;

  @override
  State<PosReturnsPage> createState() => _PosReturnsPageState();
}

class _PosReturnsPageState extends State<PosReturnsPage> {
  late final PosReturnsViewmodel _returns =
      widget.viewmodel ?? PosReturnsViewmodel();
  late final ShiftViewmodel _shift = widget.shiftViewmodel ?? ShiftViewmodel();
  final _search = TextEditingController();
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _shift.loadCurrent();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _reason.dispose();
    // Only dispose the ones we own; an injected viewmodel belongs to the caller.
    if (widget.viewmodel == null) _returns.dispose();
    if (widget.shiftViewmodel == null) _shift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PosReturnsViewmodel>.value(value: _returns),
        ChangeNotifierProvider<ShiftViewmodel>.value(value: _shift),
      ],
      child: Builder(
        builder: (context) {
          final shift = context.watch<ShiftViewmodel>();
          return DashboardShell(
            title: 'Returns',
            subtitle:
                'Return goods against the original sale — utang first, '
                'then cash.',
            selectedNavigationIndex: 6,
            navigationItems: posNavigationItems,
            onNavigationSelected: (i) => navigatePos(context, i),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height - 132,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (shift.loadError != null)
                        LiveLoadErrorBanner(
                          message: shift.loadError!,
                          onRetry: shift.loadCurrent,
                        ),
                      _gate(context, shift),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Same three states as the till: loading, unknown (a failed check is NOT
  /// "no shift"), and none. Only the last one shows the way to the Shifts tab.
  Widget _gate(BuildContext context, ShiftViewmodel shift) {
    if (shift.isLoading && shift.currentShift == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (shift.loadError != null && shift.currentShift == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: Text('The shift could not be checked.')),
      );
    }
    if (!shift.hasOpenShift) return const _NoShiftGate();
    return _returnsFlow(context);
  }

  Widget _returnsFlow(BuildContext context) {
    final returns = context.watch<PosReturnsViewmodel>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Find the original sale',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        const Text(
          'Type the transaction number on the slip or the OR number on the '
          'receipt. Only your own sales can be returned.',
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  labelText: 'Transaction or receipt number',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => returns.search(_search.text),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            FilledButton.icon(
              onPressed: returns.isSearching
                  ? null
                  : () => returns.search(_search.text),
              icon: const Icon(Icons.search),
              label: const Text('Search sale'),
            ),
          ],
        ),
        if (returns.isSearching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: LinearProgressIndicator(),
          ),
        if (returns.searchError != null)
          _errorText(context, returns.searchError!),
        if (returns.searchedMiss) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'No sale of yours matches that number. Check the slip with the '
            'customer — another till\'s sale cannot be returned here.',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
        if (returns.preflightError != null) ...[
          const SizedBox(height: AppSpacing.md),
          LiveLoadErrorBanner(
            message: returns.preflightError!,
            onRetry: returns.reloadPreflight,
          ),
        ],
        if (returns.sale case final sale?) ...[
          const SizedBox(height: AppSpacing.lg),
          _SaleHeader(sale: sale, preflight: returns.preflight),
        ],
        if (returns.preflight case final preflight?)
          if (!preflight.returnable)
            _refusal(context, returns)
          else ...[
            const SizedBox(height: AppSpacing.lg),
            _lines(context, returns, preflight),
            const SizedBox(height: AppSpacing.lg),
            _reasonField(returns),
            const SizedBox(height: AppSpacing.lg),
            _refundMethodField(returns),
            const SizedBox(height: AppSpacing.lg),
            _totals(context, returns),
            if (returns.submitError != null) ...[
              const SizedBox(height: AppSpacing.md),
              _errorText(context, returns.submitError!),
              if (returns.needsOpenShift)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: OutlinedButton.icon(
                    onPressed: () => context.go(AppRoutes.posShifts),
                    icon: const Icon(Icons.access_time),
                    label: const Text('Go to Shifts'),
                  ),
                ),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: returns.canSubmit
                  ? () => _confirmAndSubmit(context, returns)
                  : null,
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('Confirm return'),
            ),
          ],
        if (returns.result case final posted?) ...[
          const SizedBox(height: AppSpacing.lg),
          _RefundSummaryCard(result: posted),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () {
              _search.clear();
              _reason.clear();
              returns.reset();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('New return'),
          ),
        ],
      ],
    );
  }

  Widget _errorText(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  /// The server said this document cannot be reversed. Said ONCE, in the
  /// server's own code's words, with no stepper to mislead the cashier.
  Widget _refusal(BuildContext context, PosReturnsViewmodel returns) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg),
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        border: Border.all(color: AppColors.error),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Row(
        children: [
          const Icon(Icons.block, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(returns.refusalMessage ?? '')),
        ],
      ),
    ),
  );

  Widget _lines(
    BuildContext context,
    PosReturnsViewmodel returns,
    ReturnableSale preflight,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What is left to return',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final line in preflight.lines)
          _ReturnableLineRow(
            line: line,
            quantity: returns.quantityFor(line.variantUomId),
            onIncrement: () => returns.increment(line.variantUomId),
            onDecrement: () => returns.decrement(line.variantUomId),
          ),
      ],
    );
  }

  Widget _reasonField(PosReturnsViewmodel returns) => TextField(
    controller: _reason,
    maxLength: 255,
    decoration: const InputDecoration(
      labelText: 'Reason for the return (required)',
      border: OutlineInputBorder(),
    ),
    onChanged: returns.setReason,
  );

  Widget _refundMethodField(PosReturnsViewmodel returns) => Row(
    children: [
      const Text('Refund the excess by'),
      const SizedBox(width: AppSpacing.md),
      DropdownButton<String>(
        value: returns.refundMethod,
        onChanged: (value) {
          if (value != null) returns.setRefundMethod(value);
        },
        items: [
          for (final method in PosReturnsViewmodel.refundMethods)
            DropdownMenuItem(value: method, child: Text(method)),
        ],
      ),
    ],
  );

  /// The estimate, stated as an estimate: the POSTED `refund_summary` is the
  /// authority, and this line only exists so the cashier can count the money
  /// before committing.
  Widget _totals(BuildContext context, PosReturnsViewmodel returns) {
    final value = returns.returnValue;
    final debt = returns.debtReducedEstimate;
    final cash = returns.cashRefundEstimate;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _totalLine(context, 'Return value', value),
          _totalLine(context, 'Settles utang first', debt),
          _totalLine(context, 'Cash out of the drawer', cash, emphasise: true),
          if (debt > 0)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'This sale still owes money, so the return pays that down '
                'before any cash is handed over.',
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalLine(
    BuildContext context,
    String label,
    double amount, {
    bool emphasise = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          '₱${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: emphasise ? FontWeight.bold : FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Future<void> _confirmAndSubmit(
    BuildContext context,
    PosReturnsViewmodel returns,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirm the return'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${returns.lines.length} line(s) coming back.'),
            const SizedBox(height: AppSpacing.sm),
            Text('Return value ₱${returns.returnValue.toStringAsFixed(2)}'),
            Text(
              'Settles utang ₱${returns.debtReducedEstimate.toStringAsFixed(2)}',
            ),
            Text(
              'Cash refund ₱${returns.cashRefundEstimate.toStringAsFixed(2)} '
              '(${returns.refundMethod})',
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'The server settles the utang first and pays out only the '
              'excess. The refund summary afterwards is the final figure.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Post return'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await returns.submit();
  }
}

/// No open shift: the refund cannot be posted, and the way out is the Shifts
/// tab — not a retry that cannot work.
class _NoShiftGate extends StatelessWidget {
  const _NoShiftGate();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppSpacing.sm),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Open a shift before taking a return',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'A refund is cash out of the drawer, so it is counted in a '
                'shift. Open one on the Shifts tab, then come back.',
              ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => context.go(AppRoutes.posShifts),
                  icon: const Icon(Icons.access_time),
                  label: const Text('Go to Shifts'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleHeader extends StatelessWidget {
  const _SaleHeader({required this.sale, required this.preflight});

  final TransactionRecord sale;
  final ReturnableSale? preflight;

  @override
  Widget build(BuildContext context) {
    final openDebt = preflight?.openDebt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                sale.transactionNo,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: AppSpacing.md),
              Chip(label: Text(sale.source)),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('${sale.customerName} · ₱${sale.grandTotal.toStringAsFixed(2)}'),
          // The debt is the reason a credit sale's refund does not all come
          // back as cash. Stated before the cashier touches a quantity.
          if (openDebt != null && openDebt > 0)
            Text(
              'This sale still owes ₱${openDebt.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

/// One selling unit with a stepper capped at what is left.
///
/// A line with nothing left is DISABLED rather than hidden: the cashier must see
/// that the sale had that line and it has already come back.
class _ReturnableLineRow extends StatelessWidget {
  const _ReturnableLineRow({
    required this.line,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  final ReturnableLine line;
  final double quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final enabled = line.hasRemaining;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line.name} (${line.uom})',
                  style: TextStyle(
                    color: enabled ? null : AppColors.textSecondary,
                  ),
                ),
                Text(
                  enabled
                      ? '${line.remainingQty} of ${line.soldQty} left · '
                            '₱${line.unitPrice.toStringAsFixed(2)}'
                      : 'All ${line.soldQty} already returned',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: enabled && quantity > 0 ? onDecrement : null,
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'One fewer',
          ),
          SizedBox(
            width: 40,
            child: Text(
              quantity.toStringAsFixed(0),
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            onPressed: enabled && quantity < line.remainingQty
                ? onIncrement
                : null,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'One more',
          ),
        ],
      ),
    );
  }
}

/// The POSTED refund, in the server's own numbers.
///
/// Debt reduced comes before cash refund because that is the order the money
/// moved: the utang dropped first, and only the excess left the drawer.
class _RefundSummaryCard extends StatelessWidget {
  const _RefundSummaryCard({required this.result});

  final ReturnResult result;

  @override
  Widget build(BuildContext context) {
    final refund = result.refund;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Return posted: ${result.returnNo}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Return value ₱${refund.returnValue.toStringAsFixed(2)}'),
          Text('Utang reduced ₱${refund.debtReduced.toStringAsFixed(2)}'),
          Text(
            'Cash refunded ₱${refund.cashRefund.toStringAsFixed(2)} '
            '(${refund.refundMethod})',
          ),
          if (refund.ledgerBalance case final balance?)
            Text('Ledger still owes ₱${balance.toStringAsFixed(2)}')
          else
            const Text('This sale had nothing owing.'),
        ],
      ),
    );
  }
}
