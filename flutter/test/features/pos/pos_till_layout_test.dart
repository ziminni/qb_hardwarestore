// The till follows the window (2026-10-29 UI refresh). Wide: products and
// cart side by side. Narrow: the cart becomes a bar under the products and
// opens in a sheet. Short: nothing overflows and Pay stays reachable.
//
// The harness (stub repositories, open shift) is the one the pay tests use.

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
import '../../support/phase4_fakes.dart';
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
      throw const ProductsServiceException(
        'Cannot connect to the BuildPro server.',
      );
}

class _FailingInventoryRepository extends InventoryRepository {
  _FailingInventoryRepository() : super(InventoryService());

  @override
  Future<List<SystemAlert>> loadAlerts() async =>
      throw const InventoryServiceException('Cannot connect.');

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => [];
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
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
    _cart = PosTransactionViewmodel(seededInventory(), pos: _pos);
  });

  testWidgets('a wide window shows the cart beside the products', (
    tester,
  ) async {
    await _pump(tester, const Size(1600, 1000));

    expect(find.text('Proceed to payment'), findsOneWidget);
    expect(find.text('View cart'), findsNothing);
  });

  testWidgets('a narrow window moves the cart into a bar and a sheet', (
    tester,
  ) async {
    _addOneLine();
    await _pump(tester, const Size(700, 800));

    expect(find.text('View cart'), findsOneWidget);
    expect(find.text('Proceed to payment'), findsNothing);

    await tester.tap(find.text('View cart'));
    await tester.pumpAndSettle();
    expect(find.text('Proceed to payment'), findsOneWidget);

    // Pay from the sheet still reaches the payment dialog, and cancelling it
    // submits nothing (the decision 06 invariant holds on this path too).
    await tester.tap(find.text('Proceed to payment'));
    await tester.pumpAndSettle();
    expect(find.text('Payment'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_pos.calls, 0);
    expect(_cart.lines, hasLength(1));
  });

  testWidgets('the bar\'s Pay goes straight to payment', (tester) async {
    _addOneLine();
    await _pump(tester, const Size(700, 800));

    await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
    await tester.pumpAndSettle();
    expect(find.text('Payment'), findsOneWidget);
  });

  testWidgets('no window size overflows the till', (tester) async {
    _addOneLine();
    for (final size in const [
      Size(1920, 1080),
      Size(1600, 600),
      Size(1280, 720),
      Size(1000, 620),
      Size(900, 600),
      Size(700, 640),
    ]) {
      await _pump(tester, size);
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
