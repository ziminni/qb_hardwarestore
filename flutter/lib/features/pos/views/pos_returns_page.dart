import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/format/numeric_input.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/features/bodega/widgets/receipt_scanner.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_returns_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/pos/widgets/pos_return_receipt.dart';
import 'package:client/features/pos/widgets/pos_returns_bar.dart';
import 'package:client/features/pos/widgets/pos_returns_line_row.dart';
import 'package:client/features/pos/widgets/pos_returns_log_panel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  const PosReturnsPage({
    super.key,
    this.viewmodel,
    this.shiftViewmodel,
    this.scanReceipt,
    this.returnSlipPrinter,
  });

  final PosReturnsViewmodel? viewmodel;
  final ShiftViewmodel? shiftViewmodel;

  /// Optional Order Slip QR scanner override (used in tests; production uses
  /// camera scanning on mobile and USB 2D scanner focus on desktop).
  final Future<String?> Function(BuildContext context)? scanReceipt;

  /// Optional Return Slip printer override (used in tests; production uses
  /// [RollReturnSlipPrinter]).
  final ReturnSlipPrinter? returnSlipPrinter;

  @override
  State<PosReturnsPage> createState() => _PosReturnsPageState();
}

class _PosReturnsPageState extends State<PosReturnsPage> {
  late final PosReturnsViewmodel _returns =
      widget.viewmodel ?? PosReturnsViewmodel();
  late final ShiftViewmodel _shift = widget.shiftViewmodel ?? ShiftViewmodel();
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'POS returns OS scanner');
  final _reason = TextEditingController();
  final _tendered = TextEditingController();
  bool _initialSearchFocused = false;

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
    HardwareKeyboard.instance.addHandler(_onHardwareKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shift.loadCurrent();
      final salesVm = _trySalesVm(context, listen: false);
      if (salesVm != null &&
          salesVm.returns.isEmpty &&
          salesVm.sales.isEmpty &&
          !salesVm.isLoading) {
        salesVm.load(silent: true);
      }
    });
  }

  InventorySalesViewmodel? _trySalesVm(
    BuildContext context, {
    bool listen = true,
  }) {
    try {
      return Provider.of<InventorySalesViewmodel>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Captures a USB 2D QR scanner burst on the Returns page even if the cursor
  /// is not currently inside the Order Slip search field (unless another text
  /// box like Return Reason is focused).
  bool _onHardwareKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (!_shift.hasOpenShift || _returns.result != null) return false;
    if (_searchFocus.hasFocus || _searchFocus.context == null) return false;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;

    final primary = FocusManager.instance.primaryFocus;
    final primaryCtx = primary?.context;
    if (primaryCtx != null &&
        (primaryCtx.widget is EditableText ||
            primaryCtx.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }

    final kb = HardwareKeyboard.instance;
    if (kb.isControlPressed || kb.isMetaPressed || kb.isAltPressed) {
      return false;
    }

    final char = event.character;
    if (char == null || char.isEmpty || char.codeUnitAt(0) < 32) {
      return false;
    }

    _search.value = TextEditingValue(
      text: char,
      selection: TextSelection.collapsed(offset: char.length),
    );
    _searchFocus.requestFocus();
    return true;
  }

  void _restoreSearchFocus() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchFocus.context != null) {
        _searchFocus.requestFocus();
      }
    });
  }

  Future<void> _scanOrderSlipQr(
    BuildContext context,
    PosReturnsViewmodel returns,
  ) async {
    if (widget.scanReceipt != null || cameraScanAvailable) {
      final scanned = await (widget.scanReceipt ?? scanReceiptWithCamera)(
        context,
      );
      if (!mounted || scanned == null) return;
      final cleaned = scanned.trim();
      if (cleaned.isEmpty) return;
      _search.text = cleaned;
      await returns.search(cleaned);
      return;
    }
    _search.clear();
    _searchFocus.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Scanner ready — scan the Order Slip (OS) QR code now.'),
      ),
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKey);
    _search.dispose();
    _searchFocus.dispose();
    _reason.dispose();
    _tendered.dispose();
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
            title: 'Returns & Exchanges',
            subtitle:
                'Swap returned items for replacements. Cash refunds only when '
                'no replacement is available.',
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

    // Done: the server's own numbers, and the only way out is another return/exchange.
    if (returns.exchangeResult case final postedExchange?) {
      return SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _ExchangeReceiptCard(
              result: postedExchange,
              originalTransactionNo: returns.sale?.transactionNo,
              customerName: returns.sale?.customerName,
              reason: returns.reason,
              onStartAnother: () => _startAnother(returns),
            ),
          ),
        ),
      );
    }
    if (returns.result case final posted?) {
      return SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: PosReturnReceipt(
              result: posted,
              transactionNo: returns.sale?.transactionNo,
              customerName: returns.sale?.customerName,
              cashierName: returns.sale?.cashierName,
              reason: returns.reason,
              lines: _returnedLines(returns),
              printer: widget.returnSlipPrinter,
              onStartAnother: () => _startAnother(returns),
            ),
          ),
        ),
      );
    }

    if (!_initialSearchFocused) {
      _initialSearchFocused = true;
      _restoreSearchFocus();
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
                    _ReturnsProgressStepper(
                      currentStep: !refundable
                          ? 1
                          : returns.hasQuantity
                          ? 3
                          : 2,
                      isExchange: returns.mode == ReturnMode.exchange,
                    ),
                    const SizedBox(height: AppSpacing.md),
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
                    if (_trySalesVm(context) case final salesVm?) ...[
                      const SizedBox(height: AppSpacing.xl),
                      PosReturnsLogPanel(
                        returns: salesVm.returns,
                        exchanges: salesVm.sales
                            .where((s) => s.source == 'Exchange')
                            .toList(growable: false),
                        isLoading: salesVm.isLoading,
                        onRefresh: () => salesVm.load(silent: true),
                      ),
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
            'Scan the Order Slip (OS) QR code, or type the transaction / OS '
            'number. Only your own sales can be returned.',
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 260, maxWidth: 440),
                child: TextField(
                  key: const ValueKey('returns-search-field'),
                  controller: _search,
                  focusNode: _searchFocus,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Transaction or Order Slip (OS) number',
                    hintText: 'Scan OS QR or type OS-20261122-0001',
                    prefixIcon: Icon(Icons.qr_code_scanner_rounded),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => returns.search(_search.text),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('returns-scan-qr'),
                onPressed: returns.isSearching
                    ? null
                    : () => _scanOrderSlipQr(context, returns),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan OS QR'),
              ),
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
            'Type a quantity, tap All for bulk returns, or use − / +. '
            'Quantities stop at what the sale still has.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          for (final line in preflight.lines)
            PosReturnsLineRow(
              line: line,
              quantity: returns.quantityFor(line.variantUomId),
              onIncrement: () => returns.increment(line.variantUomId),
              onDecrement: () => returns.decrement(line.variantUomId),
              onQuantityChanged: (qty) =>
                  returns.setQuantity(line.variantUomId, qty),
            ),
          if (returns.hasQuantity) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(AppRadii.medium),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total return credit available',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    formatPeso(returns.returnValue),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Step 3: exchange (primary) or cash refund (only when no replacement exists).
  Widget _refundPanel(
    BuildContext context,
    PosReturnsViewmodel returns, {
    required bool showConfirm,
  }) {
    final isExchange = returns.mode == ReturnMode.exchange;
    return AppPanel(
      title: isExchange ? '3 Exchange' : '3 Refund',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<ReturnMode>(
            key: const ValueKey('returns-mode-selector'),
            segments: const [
              ButtonSegment<ReturnMode>(
                value: ReturnMode.exchange,
                icon: Icon(Icons.swap_horiz_rounded),
                label: Text('Exchange item'),
              ),
              ButtonSegment<ReturnMode>(
                value: ReturnMode.refund,
                icon: Icon(Icons.payments_outlined),
                label: Text('Refund'),
              ),
            ],
            selected: {returns.mode},
            onSelectionChanged: (selection) => returns.setMode(selection.first),
          ),
          const SizedBox(height: AppSpacing.md),
          if (isExchange) ...[
            _replacementPickerSection(context, returns),
            const SizedBox(height: AppSpacing.md),
          ] else ...[
            InkWell(
              onTap: () => returns.setNoReplacementConfirmed(
                !returns.noReplacementConfirmed,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    key: const ValueKey('returns-no-replacement-check'),
                    value: returns.noReplacementConfirmed,
                    onChanged: (checked) =>
                        returns.setNoReplacementConfirmed(checked ?? false),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No replacement item is available in store',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Cash refunds are only given when no suitable '
                          'replacement exists.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          _reasonField(returns),
          const SizedBox(height: AppSpacing.md),
          if (!isExchange || returns.exchangeExtraDue > 0) ...[
            _refundMethodField(returns),
            const SizedBox(height: AppSpacing.md),
          ],
          if (isExchange && returns.exchangeExtraDue > 0) ...[
            TextField(
              key: const ValueKey('exchange-tendered-field'),
              controller: _tendered,
              inputFormatters: decimalInputFormatters(),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText:
                    'Amount tendered (min ${formatPeso(returns.exchangeExtraDue)})',
                errorText: _tendered.text.trim().isNotEmpty &&
                        ((double.tryParse(_tendered.text.trim()) ?? 0) <
                            returns.exchangeExtraDue)
                    ? 'Enter at least ${formatPeso(returns.exchangeExtraDue)}.'
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: (raw) {
                setState(() {});
                returns.setExchangeAmountTendered(double.tryParse(raw.trim()));
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          isExchange
              ? _exchangeSummary(context, returns)
              : _summary(context, returns),
          if (showConfirm) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              key: const ValueKey('returns-confirm-button'),
              onPressed: returns.canSubmit
                  ? () => _confirmAndSubmit(context, returns)
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              icon: Icon(
                isExchange
                    ? Icons.swap_horiz_rounded
                    : Icons.assignment_return_outlined,
              ),
              label: Text(isExchange ? 'Confirm exchange' : 'Confirm return'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _replacementPickerSection(
    BuildContext context,
    PosReturnsViewmodel returns,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Replacement items',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('exchange-add-replacement'),
              onPressed: () => _pickReplacementItem(context, returns),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add item'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (returns.replacements.isEmpty)
          const Text(
            'Pick at least one replacement item to swap for the returned goods.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          )
        else
          for (final item in returns.replacements)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.name} (${item.uom}) · ${formatPeso(item.unitPrice)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    onPressed: () => returns.setReplacementQty(
                      item.variantUomId,
                      item.qty - 1,
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: TextFormField(
                      key: ValueKey(
                        'exchange-replacement-qty-${item.variantUomId}-${item.qty}',
                      ),
                      initialValue: formatQuantity(item.qty),
                      inputFormatters: decimalInputFormatters(maxDecimals: 2),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 7,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (raw) {
                        final parsed = double.tryParse(raw.trim());
                        if (parsed != null) {
                          returns.setReplacementQty(item.variantUomId, parsed);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    onPressed: () => returns.setReplacementQty(
                      item.variantUomId,
                      item.qty + 1,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Future<void> _pickReplacementItem(
    BuildContext context,
    PosReturnsViewmodel returns,
  ) async {
    InventoryViewmodel? inventory;
    try {
      inventory = context.read<InventoryViewmodel>();
    } catch (_) {
      inventory = null;
    }
    if (inventory == null) return;
    if (inventory.products.isEmpty) {
      await inventory.load();
    }
    if (!context.mounted) return;
    final options = <ExchangeReplacementLine>[];
    for (final product in inventory.products) {
      for (final variant in product.variants) {
        for (final vuom in variant.sellingUoms) {
          options.add(
            ExchangeReplacementLine(
              variantUomId: vuom.id,
              name: variant.variantName.isEmpty
                  ? product.baseName
                  : '${product.baseName} · ${variant.variantName}',
              uom: vuom.uomCode,
              unitPrice: vuom.defaultSellingPrice,
              qty: 1,
            ),
          );
        }
      }
    }
    final picked = await showDialog<ExchangeReplacementLine>(
      context: context,
      builder: (dialogContext) {
        var query = '';
        var customQty = '1';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = options.where((opt) {
              if (query.trim().isEmpty) return true;
              return opt.name.toLowerCase().contains(query.trim().toLowerCase());
            }).toList();
            final parsedQty = double.tryParse(customQty.trim());
            final validQty = parsedQty != null && parsedQty > 0 ? parsedQty : 1.0;
            return AlertDialog(
              title: const Text('Choose replacement item'),
              content: SizedBox(
                width: 460,
                height: 410,
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'Search product',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (value) =>
                                setDialogState(() => query = value),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('exchange-picker-qty-field'),
                            initialValue: customQty,
                            inputFormatters: decimalInputFormatters(
                              maxDecimals: 2,
                            ),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            decoration: InputDecoration(
                              labelText: 'Quantity',
                              errorText:
                                  customQty.trim().isNotEmpty &&
                                          (parsedQty == null || parsedQty <= 0)
                                      ? '> 0'
                                      : null,
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (value) =>
                                setDialogState(() => customQty = value),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, index) {
                          final opt = filtered[index];
                          return ListTile(
                            dense: true,
                            title: Text(opt.name),
                            subtitle: Text(opt.uom),
                            trailing: Text(
                              formatPeso(opt.unitPrice),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () => Navigator.of(
                              dialogContext,
                            ).pop(opt.copyWith(qty: validQty)),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
    if (picked != null) {
      returns.addReplacement(picked);
    }
  }

  Widget _exchangeSummary(BuildContext context, PosReturnsViewmodel returns) {
    final diff = returns.exchangeDifference;
    final headline = returns.replacements.isEmpty
        ? 'Add replacement item(s) to calculate the exchange balance.'
        : diff > 0
        ? 'Customer pays extra ${formatPeso(diff)}.'
        : diff < 0
        ? 'Cheaper swap — no cash back. Settles utang first, then store credit.'
        : 'Even swap — ₱0.00 balance.';
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
          Text(headline, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          _totalLine('Returned item credit', returns.returnValue),
          _totalLine('Replacement items', returns.replacementTotal),
          if (diff > 0)
            _totalLine('Customer pays extra', diff, emphasise: true)
          else if (diff < 0) ...[
            _totalLine('Reduces utang', returns.exchangeDebtReducedEstimate),
            _totalLine(
              'Store credit issued',
              returns.exchangeStoreCreditEstimate,
              emphasise: true,
            ),
          ] else
            _totalLine('Balance due', 0, emphasise: true),
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
    _tendered.clear();
    returns.reset();
    _restoreSearchFocus();
  }

  Future<void> _confirmAndSubmit(
    BuildContext context,
    PosReturnsViewmodel returns,
  ) async {
    // Confirm is the end of the typing: drop the keyboard BEFORE the dialog, so
    // a failed refund is not out-scrolled by the reason field taking focus back
    // and Flutter scrolling it into view again.
    FocusScope.of(context).unfocus();
    final isExchange = returns.mode == ReturnMode.exchange;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isExchange ? 'Confirm the exchange' : 'Confirm the return'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${returns.lines.length} line(s) coming back.'),
            const SizedBox(height: AppSpacing.sm),
            if (isExchange) ...[
              Text('${returns.replacements.length} replacement line(s).'),
              Text('Return credit ${formatPeso(returns.returnValue)}'),
              Text('Replacement total ${formatPeso(returns.replacementTotal)}'),
              if (returns.exchangeExtraDue > 0)
                Text(
                  'Customer pays extra ${formatPeso(returns.exchangeExtraDue)} '
                  '(${returns.refundMethod.label})',
                )
              else if (returns.exchangeDifference < 0)
                Text(
                  'No cash back: reduces utang '
                  '${formatPeso(returns.exchangeDebtReducedEstimate)}, '
                  'store credit '
                  '${formatPeso(returns.exchangeStoreCreditEstimate)}.',
                )
              else
                const Text('Even swap — ₱0.00 balance.'),
            ] else ...[
              Text(
                'Return value ${formatPeso(returns.returnValue)} '
                '(at the original prices)',
              ),
              Text('Settles utang ${formatPeso(returns.debtReducedEstimate)}'),
              Text(
                'Cash refund ${formatPeso(returns.cashRefundEstimate)} '
                '(${returns.refundMethod})',
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'The server works out the final net figures. The summary '
              'afterwards is the final record.',
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
            child: Text(isExchange ? 'Post exchange' : 'Post return'),
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
class _ReturnsProgressStepper extends StatelessWidget {
  const _ReturnsProgressStepper({
    required this.currentStep,
    required this.isExchange,
  });

  final int currentStep;
  final bool isExchange;

  @override
  Widget build(BuildContext context) {
    final steps = [
      (step: 1, title: 'Find Sale'),
      (step: 2, title: 'Choose Items & Qty'),
      (step: 3, title: isExchange ? 'Exchange Item' : 'Refund'),
    ];
    return Container(
      key: const ValueKey('returns-progress-stepper'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: steps[i].step <= currentStep
                      ? AppColors.brandGold
                      : AppColors.border,
                ),
              ),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: steps[i].step < currentStep
                        ? AppColors.successText
                        : steps[i].step == currentStep
                        ? AppColors.brandBlack
                        : AppColors.surfaceSunken,
                    child: steps[i].step < currentStep
                        ? const Icon(
                            Icons.check,
                            size: 14,
                            color: AppColors.brandWhite,
                          )
                        : Text(
                            '${steps[i].step}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: steps[i].step == currentStep
                                  ? AppColors.brandGold
                                  : AppColors.textSecondary,
                            ),
                          ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      steps[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: steps[i].step == currentStep
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: steps[i].step <= currentStep
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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

/// Server-confirmed summary of a completed item exchange.
class _ExchangeReceiptCard extends StatelessWidget {
  const _ExchangeReceiptCard({
    required this.result,
    required this.onStartAnother,
    this.originalTransactionNo,
    this.customerName,
    this.reason,
  });

  final ExchangeResult result;
  final String? originalTransactionNo;
  final String? customerName;
  final String? reason;
  final VoidCallback onStartAnother;

  @override
  Widget build(BuildContext context) {
    final s = result.summary;
    return AppPanel(
      title: 'Exchange completed · ${result.exchangeNo}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (originalTransactionNo != null)
            Text('Original sale: $originalTransactionNo'),
          if (customerName != null) Text('Customer: $customerName'),
          if (reason != null && reason!.trim().isNotEmpty)
            Text('Reason: ${reason!.trim()}'),
          const SizedBox(height: AppSpacing.md),
          _row('Return credit', formatPeso(s.returnCredit)),
          _row('Replacement total', formatPeso(s.replacementTotal)),
          if (s.netDifference > 0) ...[
            _row('Extra paid (${s.paymentMethod})', formatPeso(s.extraPaid)),
            if (s.changeGiven > 0)
              _row('Change given', formatPeso(s.changeGiven)),
          ] else if (s.netDifference < 0) ...[
            if (s.debtReduced > 0)
              _row('Utang reduced', formatPeso(s.debtReduced)),
            if (s.storeCreditIssued > 0)
              _row('Store credit issued', formatPeso(s.storeCreditIssued)),
            _row(
              'Customer store credit balance',
              formatPeso(s.customerStoreCreditBalance),
            ),
          ] else
            _row('Balance', formatPeso(0)),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onStartAnother,
            icon: const Icon(Icons.add),
            label: const Text('Start another return or exchange'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}
