import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_customer_picker_dialog.dart';
import 'package:client/features/pos/widgets/pos_payment_dialog.dart';
import 'package:client/features/pos/widgets/pos_underpayment_dialog.dart';
import 'package:client/features/pos/widgets/pos_product_browser.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/pos/widgets/pos_sale_quantity_dialog.dart';
import 'package:client/features/pos/widgets/pos_transaction_cart.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PosTransactionPage extends StatefulWidget {
  const PosTransactionPage({super.key});

  @override
  State<PosTransactionPage> createState() => _PosTransactionPageState();
}

class _PosTransactionPageState extends State<PosTransactionPage> {
  final _scanController = TextEditingController();
  final _scanFocusNode = FocusNode(debugLabel: 'POS barcode scanner');

  @override
  void dispose() {
    _scanController.dispose();
    _scanFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => PosTransactionViewmodel(
        context.read<InventoryViewmodel>(),
        context.read<ProductTrackingViewmodel>(),
      ),
      child: Builder(
        builder: (context) {
          final transaction = context.watch<PosTransactionViewmodel>();
          final products = transaction.filteredProducts;
          return DashboardShell(
            title: 'Point of Sale',
            subtitle: 'Frontend transaction and inventory simulation',
            selectedNavigationIndex: 0,
            navigationItems: const [
              DashboardNavigationItem(
                'New transaction',
                Icons.point_of_sale_outlined,
              ),
              DashboardNavigationItem(
                'Held transactions',
                Icons.pause_circle_outline,
              ),
              DashboardNavigationItem(
                'Transaction history',
                Icons.receipt_long_outlined,
              ),
              DashboardNavigationItem('Customers', Icons.people_outline),
              DashboardNavigationItem('End of shift', Icons.schedule_outlined),
            ],
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height - 132,
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
                      onChangeCustomer: () => _changeCustomer(context),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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

  /// Opens the customer picker, loading the list first.
  ///
  /// Loaded on open rather than at page start so the list is as current as the moment the
  /// cashier looks at it - a customer recorded on another terminal a minute ago should be
  /// pickable here, and the till is where that matters.
  ///
  /// Decision 14: cancelling changes NOTHING (the choice is null), "Walk-in (anonymous)" is
  /// an explicit selection rather than a cancellation, and a new customer is recorded on a
  /// name + type record and then selected.
  Future<void> _changeCustomer(BuildContext context) async {
    final transaction = context.read<PosTransactionViewmodel>();
    await transaction.loadCustomers();
    if (!context.mounted) return;

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
    if (choice == null) {
      _restoreScannerFocus();
      return;
    }
    if (!context.mounted) return;
    transaction.selectCustomer(choice.customer);
    _restoreScannerFocus();
  }

  Future<void> _pay(BuildContext context) async {    final transaction = context.read<PosTransactionViewmodel>();
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

    // Decision 06 section 4: an underpaid sale posts a receivable to the customer's
    // account, so it is confirmed BEFORE anything is submitted. Going back submits
    // nothing and leaves the cart exactly as it was.
    if (payment.amountPaid < transaction.total) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => PosUnderpaymentDialog(
          total: transaction.total,
          amountPaid: payment.amountPaid,
          customerName: 'Walk-in Customer',
        ),
      );
      if (confirmed != true || !context.mounted) {
        _restoreScannerFocus();
        return;
      }
    }

    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await transaction.submit(
      paymentMethod: payment.method,
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
