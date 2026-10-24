import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/held_cart.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_opening_float_form.dart';
import 'package:client/features/pos/widgets/pos_shift_close_dialog.dart';
import 'package:client/features/pos/widgets/pos_customer_picker_dialog.dart';
import 'package:client/features/pos/widgets/pos_payment_dialog.dart';
import 'package:client/features/pos/widgets/pos_underpayment_dialog.dart';
import 'package:client/features/pos/widgets/pos_product_browser.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/pos/widgets/pos_sale_quantity_dialog.dart';
import 'package:client/features/pos/widgets/pos_transaction_cart.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PosTransactionPage extends StatefulWidget {
  const PosTransactionPage({
    super.key,
    this.viewmodel,
    this.shiftViewmodel,
    this.heldCartViewmodel,
  });

  /// Injected by tests so the pay path can be driven WITHOUT a server.
  ///
  /// The page otherwise builds its own viewmodel, so no widget test could OBSERVE whether a
  /// submit was sent - and the "nothing is submitted" invariant (decisions 06 + 14) was verified
  /// only by reading. Same seam, and same reasoning, as SalesReceivablesPage.
  final PosTransactionViewmodel? viewmodel;

  /// The shift gate's viewmodel, injectable for the same reason: a test that
  /// pumped the till with the real one would either hit the network or be
  /// permanently stuck at the open-shift prompt.
  final ShiftViewmodel? shiftViewmodel;

  /// The parked-cart queue the Hold action writes to, and the source of a
  /// resumed basket. Injectable for tests; in the app it is the SAME instance the
  /// held-transactions tab uses, provided at the POS shell (see [main.dart]),
  /// which is what lets Resume hand a basket to this page.
  final HeldCartViewmodel? heldCartViewmodel;

  @override
  State<PosTransactionPage> createState() => _PosTransactionPageState();
}

class _PosTransactionPageState extends State<PosTransactionPage> {
  final _scanController = TextEditingController();
  final _scanFocusNode = FocusNode(debugLabel: 'POS barcode scanner');
  late final ShiftViewmodel _shiftViewmodel =
      widget.shiftViewmodel ?? ShiftViewmodel();

  /// The cart, owned here rather than created inside the provider tree.
  ///
  /// It lives on the State because TWO things drive it before the first frame's
  /// providers exist: [initState]'s pending-resume hand-off, which fills the cart
  /// from a parked basket. Reading it from the page's own context would look ABOVE
  /// the MultiProvider this widget builds and throw `ProviderNotFoundException`
  /// (reproduced by the resume test).
  late final PosTransactionViewmodel _transaction =
      widget.viewmodel ??
      PosTransactionViewmodel(
        context.read<InventoryViewmodel>(),
        context.read<ProductTrackingViewmodel>(),
      );

  late final HeldCartViewmodel _heldCarts = _resolveHeldCarts();

  /// Only set when this page had to create its own held-cart queue.
  HeldCartViewmodel? _ownedHeldCarts;

  /// Injected, else the app-level instance, else one of our own.
  ///
  /// The order matters: the shared instance is what makes Resume work at all, so
  /// a provided one is always preferred. The owned fallback only exists so a bare
  /// page (a widget test, or a route mounted without the shell) still renders.
  HeldCartViewmodel _resolveHeldCarts() {
    final injected = widget.heldCartViewmodel;
    if (injected != null) return injected;
    try {
      return context.read<HeldCartViewmodel>();
    } on ProviderNotFoundException {
      return _ownedHeldCarts = HeldCartViewmodel();
    }
  }

  @override
  void initState() {
    super.initState();
    // The catalogue boots as bundled rows (see InventoryViewmodel); the till
    // must replace them with live data on open, or the cashier sells at stale
    // prices. Found by the 6D live pass (mock 270 vs live 260 on Portland).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<InventoryViewmodel>().load();
      _shiftViewmodel.loadCurrent();
      _resumePendingCart();
    });
  }

  /// Picks up a basket the held-transactions tab handed over, if any.
  ///
  /// Runs once, on open, and CONSUMES the hand-off: the cashier sees the parked
  /// basket in the till instead of being told it exists. The cart is loaded after
  /// the first frame because the catalogue it is named from is read from the
  /// inventory viewmodel's provider, and because a resumed basket must not be
  /// loaded from inside initState where the widget tree is not ready.
  void _resumePendingCart() {
    final pending = _heldCarts.takePendingResume();
    if (pending == null) return;
    final restored = _transaction.loadHeldCart(pending);
    if (restored == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Resumed ${pending.customerLabel} · '
          '$restored line${restored == 1 ? '' : 's'}',
        ),
      ),
    );
    // The parked basket's balance is re-read for whoever it was held for, so the
    // utang panel is not blank on a basket that has one.
    _transaction.loadLedgerForSelection();
  }

  @override
  void dispose() {
    _scanController.dispose();
    _scanFocusNode.dispose();
    // Only dispose the ones we own; an injected or provided viewmodel belongs to
    // the caller / the shell.
    if (widget.shiftViewmodel == null) _shiftViewmodel.dispose();
    if (widget.viewmodel == null) _transaction.dispose();
    _ownedHeldCarts?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ShiftViewmodel>.value(value: _shiftViewmodel),
        // Provided at the till so the SAME queue the Hold action writes to is
        // the one the held-transactions tab lists.
        ChangeNotifierProvider<HeldCartViewmodel>.value(value: _heldCarts),
        ChangeNotifierProvider<PosTransactionViewmodel>.value(
          value: _transaction,
        ),
      ],
      child: Builder(
        builder: (context) {
          final shift = context.watch<ShiftViewmodel>();
          final transaction = context.watch<PosTransactionViewmodel>();
          final inventory = context.watch<InventoryViewmodel>();
          final products = transaction.filteredProducts;
          return DashboardShell(
            title: 'Point of Sale',
            subtitle: 'New transaction',
            selectedNavigationIndex: 0,
            navigationItems: posNavigationItems,
            onNavigationSelected: (i) => navigatePos(context, i),
            child: Column(
              children: [
                if (inventory.loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LiveLoadErrorBanner(
                      message: inventory.loadError!,
                      onRetry: inventory.load,
                    ),
                  ),
                if (shift.loadError != null)
                  LiveLoadErrorBanner(
                    message: shift.loadError!,
                    onRetry: shift.loadCurrent,
                  ),
                if (shift.currentShift != null) _shiftStrip(context, shift),
                _till(context, shift, transaction, products),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The till, or the reason there is no till yet.
  ///
  /// A sale rung outside a shift is refused by `process_sale` and would belong
  /// to no Z-reading (decision 06), so the gate is not a suggestion: with no
  /// open shift the product browser and cart are never built at all.
  Widget _till(
    BuildContext context,
    ShiftViewmodel shift,
    PosTransactionViewmodel transaction,
    List<PosCatalogItem> products,
  ) {
    if (shift.isLoading && shift.currentShift == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // A failed check is NOT "no shift": the banner above offers the retry, and
    // the open-shift form stays hidden so a second shift cannot be opened on
    // top of one that may still be running.
    if (shift.loadError != null && shift.currentShift == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
        child: Center(child: Text('The shift could not be checked.')),
      );
    }
    if (!shift.hasOpenShift) return const _OpenShiftGate();

    // The shift strip above the till eats its own height; without subtracting it
    // the cart's Pay button lands below the viewport, where a tap misses it.
    final stripHeight = shift.currentShift == null ? 0.0 : 48.0;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height - 132 - stripHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: PosProductBrowser(
              products: products,
              searchController: _scanController,
              searchFocusNode: _scanFocusNode,
              onSubmitted: (value) => _handleScan(context, value),
              onSearch: transaction.setQuery,
              onSelect: (product) => _addProduct(context, product),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 2,
            child: PosTransactionCart(
              onPayment: () => _pay(context),
              onClear: transaction.clear,
              onHold: () => _hold(context),
              onChangeCustomer: () => _changeCustomer(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Which shift the sales below are being counted in, and the way out of it.
  Widget _shiftStrip(BuildContext context, ShiftViewmodel shift) {
    final current = shift.currentShift!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          const Icon(Icons.access_time, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Shift open · opening float '
              '₱${current.openingFloat.toStringAsFixed(2)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: () => showShiftCloseDialog(context, shift),
            icon: const Icon(Icons.lock_outline, size: 16),
            label: const Text('Close shift'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleScan(BuildContext context, String value) async {
    final transaction = context.read<PosTransactionViewmodel>();
    final product = transaction.findByBarcode(value);
    _scanController.clear();
    transaction.setQuery('');

    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Product not found for barcode: ${value.trim()}'),
        ),
      );
      _restoreScannerFocus();
      return;
    }

    await _addProduct(context, product);
    _restoreScannerFocus();
  }

  void _restoreScannerFocus() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scanFocusNode.requestFocus();
    });
  }

  Future<void> _addProduct(BuildContext context, PosCatalogItem product) async {
    final transaction = context.read<PosTransactionViewmodel>();
    final selection = await showDialog<PosSaleSelection>(
      context: context,
      builder: (_) => PosSaleQuantityDialog(
        product: product,
        options: transaction.saleOptionsFor(product),
      ),
    );
    if (selection == null || !context.mounted) {
      _restoreScannerFocus();
      return;
    }
    final error = transaction.addLine(selection.item, selection.quantity);
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
    _restoreScannerFocus();
  }

  /// Opens the customer picker and reports whether a **named** account is selected after it.
  ///
  /// Returns false when the cashier cancelled, or chose to keep the sale anonymous - both of
  /// which must submit NOTHING when the caller is the utang path.
  Future<bool> _pickCustomer(BuildContext context) async {
    final transaction = context.read<PosTransactionViewmodel>();
    await transaction.loadCustomers();
    if (!context.mounted) return false;

    final choice = await showDialog<PosCustomerSelection>(
      context: context,
      builder: (_) => PosCustomerPickerDialog(
        customers: transaction.customers,
        loadError: transaction.customersError,
        onCreate: (name, type) async {
          final error = await transaction.createAndSelectCustomer(
            name: name,
            type: type,
          );
          if (error != null) return (null, error);
          return (transaction.selectedCustomer, null);
        },
      ),
    );
    if (choice == null) return false;
    if (!context.mounted) return false;

    transaction.selectCustomer(choice.customer);
    // Load the new account's balance, and clear it for an anonymous sale.
    await transaction.loadLedgerForSelection();
    // A customer TYPED walk-in is anonymous as far as the server is concerned, so it cannot
    // be a utang payer. Reporting "not named" here is what stops the dialog promising a
    // receivable it will refuse.
    return !transaction.isAnonymousSelection;
  }

  /// Opens the customer picker, loading the list first.
  ///
  /// Loaded on open rather than at page start so the list is as current as the moment the
  /// cashier looks at it - a customer recorded on another terminal a minute ago should be
  /// pickable here, and the till is where that matters.
  Future<void> _changeCustomer(BuildContext context) async {
    await _pickCustomer(context);
    _restoreScannerFocus();
  }

  /// Parks the basket on the server without taking money (Phase 3).
  ///
  /// Two rules, both about what is on the server afterwards:
  ///
  /// * **The till is cleared ONLY after the hold is accepted.** The basket now
  ///   lives on the server, so keeping it here would let the same items be held
  ///   twice (or sold after being parked). A failure is the opposite case: the
  ///   basket was NOT parked, so clearing would lose the customer's order.
  /// * **The account is carried across.** A basket held for a named customer is
  ///   parked against that customer, so resuming it knows who owes what.
  Future<void> _hold(BuildContext context) async {
    final transaction = context.read<PosTransactionViewmodel>();
    final heldCarts = context.read<HeldCartViewmodel>();
    // A hold with no lines would park an empty basket that resumes to nothing.
    if (transaction.lines.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final held = await heldCarts.holdCart(
      customerId: transaction.selectedCustomer?.id,
      items: [
        for (final line in transaction.lines)
          HeldCartItem(
            // `id` is read-only on the server, so a fresh line has none yet.
            id: 0,
            // A VariantUOM id, the same unit contract as checkout - see
            // decision 06 section 2 and HeldCartItemSerializer.
            variantUom: line.variantUomId,
            qty: line.quantity,
            unitPrice: line.unitPrice,
          ),
      ],
    );
    if (!context.mounted) return;

    if (held == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(heldCarts.actionError ?? 'The cart could not be held.'),
        ),
      );
      _restoreScannerFocus();
      return;
    }

    transaction.clear();
    messenger.showSnackBar(const SnackBar(content: Text('Cart held')));
    _restoreScannerFocus();
  }

  Future<void> _pay(BuildContext context) async {
    final transaction = context.read<PosTransactionViewmodel>();
    // A sale is one atomic server operation, so a double submit would be two sales.
    if (transaction.isSubmitting) return;
    final error = transaction.validate();
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      _restoreScannerFocus();
      return;
    }
    final payment = await showDialog<PosPaymentDetails>(
      context: context,
      builder: (_) => PosPaymentDialog(total: transaction.total),
    );
    if (payment == null || !context.mounted) {
      _restoreScannerFocus();
      return;
    }

    // Decision 06 section 4, extended by decision 14. An underpaid sale posts a receivable,
    // so it is confirmed BEFORE anything is submitted - and an ANONYMOUS one cannot post at
    // all (the server answers WALK_IN_CANNOT_OWE), so the cashier is given a route out rather
    // than a dead end. Nothing is submitted on any path out of here except the two that
    // explicitly say so.
    if (payment.amountPaid < transaction.total) {
      final choice = await showDialog<PosUnderpaymentChoice>(
        context: context,
        builder: (_) => PosUnderpaymentDialog(
          total: transaction.total,
          amountPaid: payment.amountPaid,
          customerName: transaction.customerLabel,
          isAnonymous: transaction.isAnonymousSelection,
        ),
      );
      if (!context.mounted) return;

      // Dismissed, and "collect the full amount", both mean SUBMIT NOTHING. The cart stays
      // exactly as it was, which is only true because this function returns here.
      if (choice == null || choice == PosUnderpaymentChoice.collectFull) {
        _restoreScannerFocus();
        return;
      }

      // An anonymous sale cannot owe, so the customer is recorded first - and if the cashier
      // does not end up with a named account, nothing is submitted.
      if (choice == PosUnderpaymentChoice.nameCustomer) {
        final named = await _pickCustomer(context);
        if (!named || !context.mounted) {
          _restoreScannerFocus();
          return;
        }
      }
    }

    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await transaction.submit(
      method: payment.method,
      amountPaid: payment.amountPaid,
    );
    if (!context.mounted) return;

    if (!confirmed) {
      // The cart is deliberately untouched. `process_sale` runs in one
      // `transaction.atomic()`, so a rejected sale rolled back wholesale - the stock
      // is unchanged and the cashier can correct the basket and retry.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            transaction.submitError ?? 'The sale could not be completed.',
          ),
        ),
      );
      _restoreScannerFocus();
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PosReceiptDialog(receipt: transaction.receipts.first),
    );
    _restoreScannerFocus();
  }
}

/// The shift gate: no open shift, no till.
///
/// The opening float is required because it is the only number the Z-reading
/// cannot reconstruct — every other figure comes from the shift's own sales.
/// The FIELD and the open call come from [PosOpeningFloatForm], shared with the
/// Shifts tab's dialog: two copies of "count the drawer" would eventually
/// disagree about what a valid float is.
class _OpenShiftGate extends StatelessWidget {
  const _OpenShiftGate();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
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
                'Open a shift to start selling',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Every sale is counted in a shift. Count the cash in the '
                'drawer and enter it as the opening float.',
              ),
              const SizedBox(height: AppSpacing.lg),
              // No onOpened: the opened shift arrives through the viewmodel,
              // and the till rebuilds into the sale screen on its own.
              const PosOpeningFloatForm(),
            ],
          ),
        ),
      ),
    );
  }
}
