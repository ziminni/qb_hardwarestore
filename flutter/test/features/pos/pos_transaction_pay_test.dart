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
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
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

late _StubPosRepository _pos;
late PosTransactionViewmodel _cart;

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
          ChangeNotifierProvider<InventoryViewmodel>.value(value: InventoryViewmodel()),
          ChangeNotifierProvider<ProductTrackingViewmodel>.value(
            value: ProductTrackingViewmodel(),
          ),
        ],
        child: MaterialApp(home: PosTransactionPage(viewmodel: _cart)),
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
    'the payment dialog REFUSES a short amount - which makes the rest of _pay unreachable',
    (tester) async {
      // FINDING (2026-10-17, found by this test and by nothing else): PosPaymentDialog's
      // validator rejects any amount below the total ("Amount is below the total"), so
      // `payment.amountPaid < transaction.total` in _pay can NEVER be true. Consequences:
      //
      //   * decision 06 section 4's underpayment confirmation step is DEAD CODE;
      //   * the whole three-way walk-in flow built as Phase 4 task 6 - "Collect the full amount"
      //     vs "Record a customer for this utang" - is UNREACHABLE through the UI;
      //   * and the server's WALK_IN_CANNOT_OWE refusal, built in Phase 4 task 2, can never fire
      //     from the till.
      //
      // Reading either file alone does not show it: the dialog looks generous, and _pay looks
      // like it handles a case that the dialog above it prevents. Nothing tested the SEAM.
      //
      // This test pins TODAY'S behaviour rather than the intended one, deliberately: it is true,
      // so it cannot pass vacuously, and it FAILS the moment someone lets a short amount through -
      // at which point it must be replaced with a real underpayment test rather than deleted.
      _addOneLine();
      await _pump(tester);
      final total = _cart.total;

      await tester.tap(find.text('Proceed to payment'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first,
        (total - 1).toStringAsFixed(2),
      );
      await tester.tap(find.text('Complete sale'));
      await tester.pumpAndSettle();

      expect(find.text('Amount is below the total'), findsOneWidget);
      expect(
        find.text('Underpayment'),
        findsNothing,
        reason: 'unreachable while the validator refuses a short amount',
      );
      expect(_pos.calls, 0, reason: 'and the sale is not submitted either');
      expect(_cart.lines, hasLength(1), reason: 'the cart stays intact');
    },
  );
}
