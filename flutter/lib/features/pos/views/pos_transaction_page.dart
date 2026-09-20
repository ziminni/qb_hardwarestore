import 'package:client/data/models/product_tracking.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_payment_dialog.dart';
import 'package:client/features/pos/widgets/pos_product_browser.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/pos/widgets/pos_sale_quantity_dialog.dart';
import 'package:client/features/pos/widgets/pos_transaction_cart.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PosTransactionPage extends StatelessWidget {
  const PosTransactionPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PosTransactionViewmodel(),
      child: Builder(
        builder: (context) {
          final transaction = context.watch<PosTransactionViewmodel>();
          final inventory = context.watch<ProductTrackingViewmodel>();
          final products = transaction.filteredProducts(
            inventory.configurations,
          );
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

  Future<void> _addProduct(
    BuildContext context,
    ProductTrackingConfiguration product,
  ) async {
    final selection = await showDialog<({double quantity, String unit})>(
      context: context,
      builder: (_) => PosSaleQuantityDialog(product: product),
    );
    if (selection == null || !context.mounted) return;
    final inventory = context.read<ProductTrackingViewmodel>();
    final validation = inventory.validateSale(
      product.productName,
      selection.quantity,
      selection.unit,
    );
    if (!validation.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validation.message)));
      return;
    }
    context.read<PosTransactionViewmodel>().addLine(
      product,
      selection.quantity,
      selection.unit,
    );
  }

  Future<void> _pay(BuildContext context) async {
    final transaction = context.read<PosTransactionViewmodel>();
    final inventory = context.read<ProductTrackingViewmodel>();
    final validation = transaction.validate(inventory);
    if (!validation.success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validation.message)));
      return;
    }
    final payment = await showDialog<PosPaymentDetails>(
      context: context,
      builder: (_) => PosPaymentDialog(total: transaction.total),
    );
    if (payment == null || !context.mounted) return;
    final receipt = transaction.complete(
      inventory: inventory,
      paymentMethod: payment.method,
      amountPaid: payment.amountPaid,
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PosReceiptDialog(receipt: receipt),
    );
  }
}
