// Task 19's last item: PosTransactionPage._pay/_pickCustomer, which holds the "nothing is
// submitted" invariant from decisions 06 and 14.
//
// Why this matters more than any other gap on this branch: a wrong answer here does not render a
// wrong number, it CREATES A REAL DEBT or A SECOND SALE.
//
// This test was blocked TWICE before it could run at all, by two defects in shared UI rather than
// in any POS screen: a ListTile inside a ColoredBox in DashboardShell (fixed - the colour moved to
// a Material), and an undefended Row in SystemBrand that overflowed the fixed 220px sidebar
// (fixed - Flexible plus ellipsis). Both were real, and neither could be seen from the POS code.
//
// Three of _pay's six paths are covered here; the other three are enumerated in the ledger.

import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubPosRepository extends PosRepository {
  _StubPosRepository() : super(PosService());

  int calls = 0;

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
    return PosCheckoutResult(
      id: 1,
      transactionNo: 'TRX-1',
      orNumber: 'OR-1',
      transDate: DateTime(2026, 10, 17, 10),
      grandTotal: 0,
    );
  }
}

/// The till is gated on an open shift (decision 06: `process_sale` refuses a
/// sale with none), so every pay test needs one open or `_pay` is never
/// reachable — the gate would be the only thing on screen.
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

// The till loads the live catalogue on open (6D). These stubs fail
// deterministically so the page never touches the network: with real
// repositories the tests would pass against a dead server and behave
// differently with a live one (mock rows swapped mid-test).
class _FailingProductsRepository extends ProductsRepository {
  _FailingProductsRepository() : super(ProductsService());

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      throw const ProductsServiceException('Cannot connect to the BuildPro server.');
}

class _FailingInventoryRepository extends InventoryRepository {
  _FailingInventoryRepository() : super(InventoryService());

  @override
  Future<List<SystemAlert>> loadAlerts() async =>
      throw const InventoryServiceException('Cannot connect.');

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => [];
}

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
          ChangeNotifierProvider<InventoryViewmodel>.value(
            value: InventoryViewmodel(
              products: _FailingProductsRepository(),
              inventory: _FailingInventoryRepository(),
            ),
          ),
          ChangeNotifierProvider<ProductTrackingViewmodel>.value(
            value: ProductTrackingViewmodel(),
          ),
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

void _addOneLine() {
  final item = _cart.filteredProducts.first;
  final option = _cart.saleOptionsFor(item).first;
  expect(_cart.addLine(option, 1), isNull, reason: 'the line must be addable');
}

void main() {
  setUp(() {
    _pos = _StubPosRepository();
    _cart = PosTransactionViewmodel(
      InventoryViewmodel(),
      ProductTrackingViewmodel(),
      pos: _pos,
    );
  });

  testWidgets('an EMPTY cart cannot reach payment at all', (tester) async {
    await _pump(tester);

    final pay = tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(pay.onPressed, isNull, reason: 'a zero-value receipt is not a sale');
    expect(_pos.calls, 0);
  });

  testWidgets('dismissing the payment dialog submits NOTHING', (tester) async {
    _addOneLine();
    await _pump(tester);

    await tester.tap(find.text('Proceed to payment'));
    await tester.pumpAndSettle();
    expect(find.text('Payment'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(_pos.calls, 0, reason: 'the cashier changed their mind');
    expect(_cart.lines, hasLength(1), reason: 'and the cart is untouched');
  });

  testWidgets(
    'a SHORT amount is ACCEPTED and reaches decision 06 section 4',
    (tester) async {
      // #21, resolved 2026-10-17: the validator was wrong, not the flow. A short amount records an
      // utang, so the dialog must WARN rather than block - and _pay's section 4 confirmation, the
      // three-way walk-in flow, and the server's WALK_IN_CANNOT_OWE guard all become reachable.
      //
      // This REPLACES the test that pinned the old refusal. That test said of itself: "it FAILS the
      // moment someone lets a short amount through - at which point it must be replaced with a real
      // underpayment test rather than deleted." This is that test.
      _addOneLine();
      await _pump(tester);
      final total = _cart.total;

      await tester.tap(find.text('Proceed to payment'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first,
        (total - 70).toStringAsFixed(2),
      );
      await tester.pumpAndSettle();

      // The warning must name what is unpaid: it is the only thing between a mistyped amount and an
      // unintended receivable.
      expect(find.textContaining('will be left unpaid'), findsOneWidget);
      expect(find.text('Amount is below the total'), findsNothing);

      await tester.tap(find.text('Complete sale'));
      await tester.pumpAndSettle();

      // The seam: the short amount got through, so section 4 opened instead of the sale posting.
      expect(find.text('Underpayment'), findsOneWidget);
      expect(_pos.calls, 0, reason: 'section 4 confirms BEFORE anything is submitted');
      expect(_cart.lines, hasLength(1), reason: 'the cart stays intact');
    },
  );
}
