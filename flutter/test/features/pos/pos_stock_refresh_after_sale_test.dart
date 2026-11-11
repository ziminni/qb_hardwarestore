// FX9 (QA wave 3b, Low): the receipt for a completed sale appears over a
// dimmed product card that still reads the PRE-sale stock — "100 pc in stock"
// over a batch the server already held at 99. The value was only refreshed when
// the cashier pressed "New transaction".
//
// The sale is the one moment the catalogue is certainly stale, so `_pay` asks
// the same store the cards read for a reload as soon as the server confirms,
// and does it while the receipt is on screen rather than after it.

import 'package:client/data/models/product.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// The server's catalogue, in two states: 100 on hand while the cashier is
/// selling, 99 once the sale is written. Nothing else changes, which is what
/// makes the card's label a direct read of the refresh.
class _StockAfterSale extends ProductsRepository {
  _StockAfterSale() : super(ProductsService());

  bool sold = false;
  int loads = 0;

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    loads++;
    return ProductsSnapshot(
      products: seededProducts(),
      batches: [
        batch(
          id: 1,
          variantId: 1,
          qty: sold ? 99 : 100,
          cost: 235,
          receiptId: 1,
        ),
        batch(id: 2, variantId: 2, qty: 40, cost: 70, receiptId: 2),
      ],
    );
  }
}

class _StubPosRepository extends PosRepository {
  _StubPosRepository() : super(PosService());

  int calls = 0;

  /// What the server does inside the sale's own transaction: the stock the
  /// catalogue reports next time has one unit less.
  VoidCallback? onCheckout;

  @override
  Future<int> walkInCustomerId() async => 1;

  @override
  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
    String? idempotencyKey,
  }) async {
    calls++;
    onCheckout?.call();
    return PosCheckoutResult(
      id: 1,
      transactionNo: 'TRX-1',
      orNumber: 'OR-1',
      transDate: DateTime(2026, 10, 17, 10),
      grandTotal: 0,
    );
  }
}

class _OpenShift extends ShiftService {
  @override
  Future<Shift?> fetchCurrent() async => Shift(
    id: 1,
    cashierName: 'Ana Cruz',
    status: Shift.openStatus,
    openingFloat: 5000,
    closingCount: null,
    openedAt: DateTime(2026, 10, 21, 8),
    closedAt: null,
    notes: '',
    zReading: null,
  );
}

late _StubPosRepository _pos;
late PosTransactionViewmodel _cart;
late InventoryViewmodel _inventory;
late _StockAfterSale _products;

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryViewmodel>.value(value: _inventory),
        ],
        child: MaterialApp(
          home: PosTransactionPage(
            viewmodel: _cart,
            shiftViewmodel: ShiftViewmodel(service: _OpenShift()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The product cards' stock badge, e.g. "100 bag in stock" (the badge lowercases
/// the unit itself).
Finder _stockBadge(String label) => find.text(label);

List<Product> _productsList() => seededProducts();

void main() {
  setUp(() {
    _products = _StockAfterSale();
    _pos = _StubPosRepository()..onCheckout = () => _products.sold = true;
    // One instance for the page, the cart AND the reload: production shares the
    // app-scoped store, and the whole point of this fix is that the reload
    // reaches the cards.
    _inventory = InventoryViewmodel(
      products: _products,
      inventory: FakeInventoryRepository(),
      catalogue: FakeCatalogueRepository(),
    );
    _cart = PosTransactionViewmodel(_inventory, pos: _pos);
  });

  testWidgets('a completed sale refreshes the stock behind the receipt', (
    tester,
  ) async {
    // The catalogue the cards read: 100 on hand before the sale.
    await _pump(tester);
    expect(_productsList(), isNotEmpty);
    expect(_stockBadge('100 bag in stock'), findsOneWidget);
    expect(_products.loads, 1);

    final item = _cart.filteredProducts.first;
    expect(_cart.addLine(_cart.saleOptionsFor(item).first, 1), isNull);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Proceed to payment'));
    await tester.pumpAndSettle();
    // Pay the exact total: the payment dialog prefills nothing, and a short
    // amount would open the underpayment path instead of the sale.
    await tester.enterText(
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          )
          .first,
      _cart.total.toStringAsFixed(2),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    await tester.pumpAndSettle();

    expect(_pos.calls, 1, reason: 'the sale posted');
    expect(
      find.byType(PosReceiptDialog),
      findsOneWidget,
      reason: 'the receipt is still on screen',
    );
    expect(
      _stockBadge('99 bag in stock'),
      findsOneWidget,
      reason: 'the dimmed card behind the receipt must not show the old count',
    );
    expect(_stockBadge('100 bag in stock'), findsNothing);
    expect(
      _products.loads,
      2,
      reason: 'a completed sale reloads the catalogue the cards read',
    );
  });
}
