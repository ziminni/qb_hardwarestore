import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/pos_returns_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/pos/widgets/pos_return_receipt.dart';
import 'package:client/features/pos/widgets/pos_returns_bar.dart';
import 'package:client/features/pos/widgets/pos_returns_line_row.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// The till's Returns tab (index 6, decision 05).
///
/// A customer comes back with goods and a slip. The cashier works through three
/// numbered steps: find the original sale, choose what comes back, then refund.
/// The server decides the money: the return value settles the utang first and
/// only the excess leaves the drawer.
///
/// No open shift, no refund: a refund is cash out of a drawer, and a drawer is a
/// shift. The gate is the same one the till uses, and for the same reason, an
/// orphan refund makes the Z-reading's expected drawer too high.
///
/// Layout (C7): narrow windows stack the steps and pin the refund and Confirm to
/// the bottom ([PosReturnsBar]); a wide window puts steps 2 and 3 side by side so
/// the summary stays visible while the cashier steps quantities. The page owns
/// its one scroll region ([DashboardShell.scrollable] is false), so there is no
/// scroll inside a scroll and the padding is the shell's own.
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

  /// The one scroll region the page owns, so a failed refund can bring the
  /// reason it failed to the top of the screen instead of leaving it below the
  /// fold (and below the pinned bar) where the cashier never sees it.
  final _scroll = ScrollController();

  /// Below this content width steps 2 and 3 stack and the refund pins to the
  /// bottom. Measured on the content box, not the window, so the sidebar can
  /// take its width first.
  static const double _sideBySideMinWidth = 900;

  /// The refund summary's fixed column when the steps sit side by side.
  static const double _refundPanelWidth = 360;

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
    _scroll.dispose();
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
                'Return goods against the original sale. Utang is cleared '
                'first, then cash.',
            selectedNavigationIndex: 6,
            navigationItems: posNavigationItems,
            onNavigationSelected: (i) => navigatePos(context, i),
            // The page keeps the refund bar on screen by scrolling its own
            // steps, so the shell hands it the height under the header.
            scrollable: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (shift.loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: LiveLoadErrorBanner(
                      message: shift.loadError!,
                      onRetry: shift.loadCurrent,
                    ),
                  ),
                Expanded(child: _gate(context, shift)),
              ],
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
      return const Center(child: CircularProgressIndicator());
    }
    if (shift.loadError != null && shift.currentShift == null) {
      return const Center(child: Text('The shift could not be checked.'));
    }
    if (!shift.hasOpenShift) {
      return const SingleChildScrollView(child: _NoShiftGate());
    }
    return _returnsFlow(context);
  }

  Widget _returnsFlow(BuildContext context) {
    final returns = context.watch<PosReturnsViewmodel>();

    // Done: the server's own numbers, and the only way out is another return.
    if (returns.result case final posted?) {
      return SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: PosReturnReceipt(
              result: posted,
              transactionNo: returns.sale?.transactionNo,
              lines: _returnedLines(returns),
              onStartAnother: () => _startAnother(returns),
            ),
          ),
        ),
      );
    }

    final preflight = returns.preflight;
    final refundable = preflight != null && preflight.returnable;
    // Nothing looked up yet: say what this screen is for, rather than leaving
    // the lower half of the window blank.
    final untouched =
        returns.sale == null &&
        !returns.searchedMiss &&
        !returns.isSearching &&
        returns.searchError == null &&
        returns.preflightError == null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _sideBySideMinWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ONE failure, above the steps: the refund's refusal must not
                    // hide under the pinned bar where the cashier tapped.
                    if (returns.submitError case final error?) ...[
                      ErrorBanner(message: error),
                      if (returns.needsOpenShift)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => context.go(AppRoutes.posShifts),
                              icon: const Icon(Icons.access_time),
                              label: const Text('Go to Shifts'),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    _findPanel(context, returns),
                    if (untouched) ...[
                      const SizedBox(height: AppSpacing.lg),
                      AppPanel(
                        child: EmptyState(
                          icon: Icons.assignment_return_outlined,
                          message:
                              'No sale chosen yet. Search the number on the '
                              'slip and the goods that can still come back are '
                              'listed here.',
                        ),
                      ),
                    ],
                    if (preflight != null && !preflight.returnable) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _refusalPanel(context, returns),
                    ] else if (preflight != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _choosePanel(context, returns, preflight),
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            SizedBox(
                              width: _refundPanelWidth,
                              // Confirm lives in the step here: both panels are
                              // on screen, so nothing needs pinning.
                              child: _refundPanel(
                                context,
                                returns,
                                showConfirm: true,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _choosePanel(context, returns, preflight),
                        const SizedBox(height: AppSpacing.lg),
                        // Confirm is in the bar below, never twice on screen.
                        _refundPanel(context, returns, showConfirm: false),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            if (!wide && refundable) ...[
              const SizedBox(height: AppSpacing.md),
              PosReturnsBar(
                returnValue: returns.returnValue,
                cashRefund: returns.cashRefundEstimate,
                canConfirm: returns.canSubmit,
                onConfirm: () => _confirmAndSubmit(context, returns),
              ),
            ],
          ],
        );
      },
    );
  }

  /// What came back, named, for the receipt. The chosen quantities are still on
  /// the viewmodel until the cashier starts another return.
  List<({String name, String uom, double qty})> _returnedLines(
    PosReturnsViewmodel returns,
  ) => [
    for (final line in returns.preflight?.lines ?? const <ReturnableLine>[])
      if (returns.quantityFor(line.variantUomId) > 0)
        (
          name: line.name,
          uom: line.uom,
          qty: returns.quantityFor(line.variantUomId),
        ),
  ];

  /// Step 1: the original sale, and what the server says the cashier may do
  /// with it.
  Widget _findPanel(BuildContext context, PosReturnsViewmodel returns) {
    final sale = returns.sale;
    return AppPanel(
      title: '1 Find the sale',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
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
            const Text(
              'No sale of yours matches that number. Check the slip with the '
              'customer, because another till\'s sale cannot be returned here.',
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
          if (sale != null && returns.preflight != null) ...[
            const SizedBox(height: AppSpacing.md),
            _SaleHeader(sale: sale, preflight: returns.preflight),
          ],
        ],
      ),
    );
  }

  /// Step 2: one row per selling unit, each with the till's stepper.
  Widget _choosePanel(
    BuildContext context,
    PosReturnsViewmodel returns,
    ReturnableSale preflight,
  ) {
    return AppPanel(
      title: '2 Choose items',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Step the quantities that are coming back. The stepper stops at '
            'what the sale still has.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          for (final line in preflight.lines)
            PosReturnsLineRow(
              line: line,
              quantity: returns.quantityFor(line.variantUomId),
              onIncrement: () => returns.increment(line.variantUomId),
              onDecrement: () => returns.decrement(line.variantUomId),
            ),
        ],
      ),
    );
  }

  /// Step 3: why, how the excess is paid, and the live split between the utang
  /// and the drawer.
  Widget _refundPanel(
    BuildContext context,
    PosReturnsViewmodel returns, {
    required bool showConfirm,
  }) {
    return AppPanel(
      title: '3 Refund',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _reasonField(returns),
          const SizedBox(height: AppSpacing.md),
          _refundMethodField(returns),
          const SizedBox(height: AppSpacing.md),
          _summary(context, returns),
          if (showConfirm) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: returns.canSubmit
                  ? () => _confirmAndSubmit(context, returns)
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('Confirm return'),
            ),
          ],
        ],
      ),
    );
  }

  /// The server said this document cannot be reversed. Said ONCE, in the
  /// server's own code's words, with no stepper to mislead the cashier.
  Widget _refusalPanel(BuildContext context, PosReturnsViewmodel returns) {
    return AppPanel(
      child: Row(
        children: [
          const Icon(Icons.block, color: AppColors.errorText),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              returns.refusalMessage ?? '',
              style: const TextStyle(color: AppColors.errorText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorText(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

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
      const Expanded(child: Text('Refund the excess by')),
      // Boxed like the till's fields: a bare underlined dropdown read as loose
      // text next to the bordered inputs above it.
      DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<TenderMethod>(
              value: returns.refundMethod,
              onChanged: (value) {
                if (value != null) returns.setRefundMethod(value);
              },
              // Labels on screen, codes on the wire (C1): the refund POST carries
              // `payment_method: 'CASH'`, never the word the cashier read.
              items: [
                for (final method in PosReturnsViewmodel.refundMethods)
                  DropdownMenuItem(value: method, child: Text(method.label)),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  /// The estimate, stated as a sentence the cashier can say to the customer,
  /// plus the breakdown behind it. The POSTED `refund_summary` is the authority;
  /// this only exists so the cashier can count the money before committing.
  Widget _summary(BuildContext context, PosReturnsViewmodel returns) {
    final value = returns.returnValue;
    final debt = returns.debtReducedEstimate;
    final cash = returns.cashRefundEstimate;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.selected,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _summarySentence(debt: debt, cash: cash),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          _totalLine('Return value', value),
          _totalLine('Settles utang first', debt),
          _totalLine('Cash out of the drawer', cash, emphasise: true),
          if (debt > 0)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'This sale still owes money, so the return pays that down '
                'before any cash is handed over.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  /// One sentence, always both figures: what the utang absorbs and what leaves
  /// the drawer. A zero is never dressed up as a refund.
  static String _summarySentence({required double debt, required double cash}) {
    if (debt <= 0 && cash <= 0) {
      return 'Nothing to refund yet. Choose the quantities that are coming '
          'back.';
    }
    if (debt > 0 && cash > 0) {
      return 'Clears ${formatPeso(debt)} of utang, refunds ${formatPeso(cash)} '
          'in cash.';
    }
    if (debt > 0) {
      return 'Clears ${formatPeso(debt)} of utang. No cash leaves the drawer.';
    }
    return 'Refunds ${formatPeso(cash)} in cash.';
  }

  Widget _totalLine(String label, double amount, {bool emphasise = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              formatPeso(amount),
              style: TextStyle(
                fontWeight: emphasise ? FontWeight.bold : FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );

  void _startAnother(PosReturnsViewmodel returns) {
    _search.clear();
    _reason.clear();
    returns.reset();
  }

  Future<void> _confirmAndSubmit(
    BuildContext context,
    PosReturnsViewmodel returns,
  ) async {
    // Confirm is the end of the typing: drop the keyboard BEFORE the dialog, so
    // a failed refund is not out-scrolled by the reason field taking focus back
    // and Flutter scrolling it into view again.
    FocusScope.of(context).unfocus();
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
            Text(
              'Return value ${formatPeso(returns.returnValue)} '
              '(at the original prices)',
            ),
            Text('Settles utang ${formatPeso(returns.debtReducedEstimate)}'),
            Text(
              'Cash refund ${formatPeso(returns.cashRefundEstimate)} '
              '(${returns.refundMethod})',
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'A discounted sale refunds its net share, which the server works '
              'out. The refund summary afterwards is the final figure.',
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
    final posted = await returns.submit();
    // A refusal is stated at the TOP of the page; bring it into view rather
    // than leaving the cashier looking at a Confirm button that did nothing.
    if (!posted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }
}

/// No open shift: the refund cannot be posted, and the way out is the Shifts
/// tab, not a retry that cannot work.
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
            color: AppColors.cardBackground,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadii.large),
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
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
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

/// The sale the goods came back from, and what it still owes.
class _SaleHeader extends StatelessWidget {
  const _SaleHeader({required this.sale, required this.preflight});

  final TransactionRecord sale;
  final ReturnableSale? preflight;

  @override
  Widget build(BuildContext context) {
    final openDebt = preflight?.openDebt;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  sale.transactionNo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              StatusBadge(label: sale.source),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${sale.customerName} · ${formatPeso(sale.grandTotal)} · '
            '${formatDate(sale.transDate)}',
          ),
          // The debt is the reason a credit sale's refund does not all come
          // back as cash. Stated before the cashier touches a quantity.
          if (openDebt != null && openDebt > 0)
            Text(
              'This sale still owes ${formatPeso(openDebt)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}
