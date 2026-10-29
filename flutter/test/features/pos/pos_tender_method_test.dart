// C1 — the till could not sell (live browser QA, 2026-10-24).
//
// The payment dialog's dropdown held the DISPLAY LABELS ('Cash', 'GCash', 'Card') and
// `_pay` handed whichever one was picked straight to `submit`, which put it in the POST
// body as `payments[].method`. The server has validated that field strictly since Phase 1
// (`3c2349e`), so every sale at the counter was refused:
//
//   400 INVALID_SALE — "Payment 1: 'Cash' is not a payment method this till takes."
//
// WHY THE EXISTING TESTS MISSED IT: every checkout test called `submit(paymentMethod:
// 'CASH', ...)` with the WIRE CODE already in hand (pos_transaction_submit_test.dart) or
// stubbed the repository and never looked at the payload (pos_transaction_pay_test.dart).
// Nothing drove the real dialog into the real payload, so the label/code seam — the only
// place the bug lived — was never crossed by a test.
//
// These tests cross it: tap the dropdown, pick a tender, press "Complete sale", and read
// what the repository was asked to send.

import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/pos_transaction.dart' show PosReceipt;
import 'package:client/data/models/shift.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import '../../support/phase4_fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _RecordingPosRepository extends PosRepository {
  _RecordingPosRepository() : super(PosService());

  int calls = 0;
  List<PosCheckoutPayment> sentPayments = const [];

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
    sentPayments = payments;
    return PosCheckoutResult(
      id: 1,
      transactionNo: 'TRX-1',
      orNumber: 'OR-1',
      transDate: DateTime(2026, 10, 24, 10),
      grandTotal: 20,
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
    openedAt: DateTime(2026, 10, 24, 8),
    closedAt: null,
    notes: '',
    zReading: null,
  );
}

class _FailingProductsRepository extends ProductsRepository {
  _FailingProductsRepository() : super(ProductsService());

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      throw const ProductsServiceException('Cannot connect.');
}

class _FailingInventoryRepository extends InventoryRepository {
  _FailingInventoryRepository() : super(InventoryService());

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => [];
}

late _RecordingPosRepository _pos;
late PosTransactionViewmodel _cart;

Future<void> _pumpTill(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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

/// Opens the payment dialog, picks [label] and completes the sale.
Future<void> _payWith(WidgetTester tester, {String? label}) async {
  await tester.tap(find.text('Proceed to payment'));
  await tester.pumpAndSettle();
  expect(find.text('Payment'), findsOneWidget);

  if (label != null) {
    // The field shows the CURRENT choice; tapping it opens the menu.
    await tester.tap(find.byType(DropdownButtonFormField<TenderMethod>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  await tester.tap(find.text('Complete sale'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _pos = _RecordingPosRepository();
    _cart = PosTransactionViewmodel(seededInventory(), pos: _pos);
    final option = _cart.saleOptionsFor(_cart.filteredProducts.first).first;
    expect(_cart.addLine(option, 1), isNull);
  });

  group('the till sends the WIRE CODE, never the display label', () {
    testWidgets('Cash (the default) posts method CASH', (tester) async {
      await _pumpTill(tester);
      await _payWith(tester);

      expect(_pos.calls, 1, reason: 'the sale must actually reach the server');
      expect(
        _pos.sentPayments.single.method,
        'CASH',
        reason:
            'the server accepts Payment.Method codes only (Phase 1, 3c2349e); '
            "'Cash' is answered with 400 INVALID_SALE",
      );
    });

    testWidgets('GCash posts method GCASH', (tester) async {
      await _pumpTill(tester);
      await _payWith(tester, label: 'GCash');

      expect(_pos.calls, 1);
      expect(_pos.sentPayments.single.method, 'GCASH');
    });

    testWidgets('Card posts method CARD', (tester) async {
      await _pumpTill(tester);
      await _payWith(tester, label: 'Card');

      expect(_pos.calls, 1);
      expect(_pos.sentPayments.single.method, 'CARD');
    });
  });

  group('the receipt shows the LABEL the cashier picked', () {
    PosReceipt receipt(String method) => PosReceipt(
      reference: 'TRX-1',
      officialReceiptNumber: 'OR-1',
      createdAt: DateTime(2026, 10, 24, 10),
      lines: const [],
      paymentMethod: method,
      amountPaid: 20,
      total: 20,
    );

    Future<void> pumpReceipt(WidgetTester tester, String method) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PosReceiptDialog(receipt: receipt(method))),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a wire code is rendered as its label', (tester) async {
      await pumpReceipt(tester, 'CASH');
      expect(find.text('Payment: Cash'), findsOneWidget);
    });

    testWidgets('a legacy label row does not crash the receipt', (
      tester,
    ) async {
      // Pre-Phase-1 sales stored 'Cash' in the database. Display must tolerate them.
      await pumpReceipt(tester, 'Cash');
      expect(find.text('Payment: Cash'), findsOneWidget);
    });
  });
}
