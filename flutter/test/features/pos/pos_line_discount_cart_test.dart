// A cashier giving a discount on ONE cart line at the till.
//
// Two things the model and the viewmodel cannot prove: that the cashier can reach
// the discount from the cart line and SEE the discounted amount afterwards, and that
// a line discount alone still opens the manager approval when it is above the cap
// (the server measures line + sale discounts together).

import 'package:client/data/models/sale_discount.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/discount_approval_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_payment_dialog.dart';
import 'package:client/features/pos/widgets/pos_transaction_cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/payment_steps.dart';
import '../../support/phase4_fakes.dart';

class _StubPosRepository extends PosRepository {
  _StubPosRepository() : super(PosService());

  @override
  Future<int> walkInCustomerId() async => 1;

  @override
  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
    String? idempotencyKey,
    PosDiscount? discount,
    String? discountApproval,
    dynamic delivery,
    bool creditSale = false,
  }) async => PosCheckoutResult(
    id: 1,
    transactionNo: 'TRX-1',
    orNumber: 'OR-1',
    transDate: DateTime(2026, 11, 20, 10),
    grandTotal: 540,
  );
}

class _FakeApprovalService extends DiscountApprovalService {
  int calls = 0;
  double lastPercent = 0;
  String lastReason = '';

  @override
  Future<DiscountApproval> request({
    required String username,
    required String password,
    required double percent,
    required String reason,
  }) async {
    calls++;
    lastPercent = percent;
    lastReason = reason;
    return DiscountApproval(
      token: 'TOKEN-1',
      percent: percent,
      approver: 'Store Manager',
    );
  }
}

void main() {
  late InventoryViewmodel inventory;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = seededInventory();
    cart = PosTransactionViewmodel(inventory, pos: _StubPosRepository());
    // Two bags of Portland Cement at 270: 540.
    final option = cart.saleOptionsFor(cart.filteredProducts.first).first;
    expect(cart.addLine(option, 2), isNull);
  });

  Future<void> pumpCart(WidgetTester tester) async {
    tester.view.physicalSize = const Size(760, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<PosTransactionViewmodel>.value(
        value: cart,
        child: MaterialApp(
          home: Scaffold(
            body: PosTransactionCart(
              onPayment: () {},
              onClear: () {},
              onChangeCustomer: () {},
              onHold: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a cashier adds a line discount and sees the discounted line', (
    tester,
  ) async {
    await pumpCart(tester);

    await tester.tap(find.byKey(const ValueKey('pos-line-discount-open-0')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('pos-line-discount-value')),
      '40',
    );
    await tester.enterText(
      find.byKey(const ValueKey('pos-line-discount-reason')),
      'chipped bag',
    );
    await tester.tap(find.byKey(const ValueKey('pos-line-discount-save')));
    await tester.pumpAndSettle();

    expect(cart.lines.single.discount?.value, 40);
    // The line is now 500, labelled as discounted, and the sale total follows.
    expect(
      find.byKey(const ValueKey('pos-line-discount-label-0')),
      findsOneWidget,
    );
    // The line shows what it now costs, with the amount taken off beside the reason.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('pos-line-discount-label-0')),
        matching: find.text('-₱40.00'),
      ),
      findsOneWidget,
    );
    expect(find.text('₱500.00'), findsWidgets);
    expect(find.text('₱540.00'), findsOneWidget, reason: 'the gross subtotal');
    expect(
      find.byKey(const ValueKey('pos-cart-line-discount-section')),
      findsOneWidget,
    );
    expect(cart.total, 500);
  });

  testWidgets('a line discount with no reason is refused', (tester) async {
    await pumpCart(tester);
    await tester.tap(find.byKey(const ValueKey('pos-line-discount-open-0')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('pos-line-discount-value')),
      '40',
    );
    await tester.tap(find.byKey(const ValueKey('pos-line-discount-save')));
    await tester.pumpAndSettle();

    expect(find.text('A discount needs a reason'), findsOneWidget);
    expect(cart.lines.single.discount, isNull);
  });

  testWidgets('Hold stays enabled when a line discount exists', (
    tester,
  ) async {
    cart.setLineDiscount(
      0,
      const PosDiscount(
        kind: DiscountKind.amount,
        value: 40,
        reason: 'chipped bag',
      ),
    );
    await pumpCart(tester);

    final hold = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Hold transaction'),
    );
    expect(hold.onPressed, isNotNull);
    expect(find.byKey(const ValueKey('pos-cart-hold-blocked')), findsNothing);
  });

  testWidgets('a line discount alone above the cap asks for approval', (
    tester,
  ) async {
    // 20% off the line, no sale discount: 108 of 540 is over a 10% cap.
    cart.setLineDiscount(
      0,
      const PosDiscount(
        kind: DiscountKind.percent,
        value: 20,
        reason: 'damaged packaging',
      ),
    );
    final approval = _FakeApprovalService();
    PosPaymentDetails? details;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                details = await showDialog<PosPaymentDetails>(
                  context: context,
                  builder: (_) => PosPaymentDialog(
                    total: cart.total,
                    discountCapPercent: 10,
                    approvalService: approval,
                    cart: cart,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await completePayment(tester);
    await tester.pumpAndSettle();

    expect(find.text('Manager approval needed'), findsOneWidget);
    expect(approval.calls, 0, reason: 'nothing asked before the password');

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Approver username'),
      'manager',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'correct horse',
    );
    await tester.tap(find.text('Approve discount'));
    await tester.pumpAndSettle();

    expect(approval.calls, 1);
    expect(approval.lastPercent, closeTo(20, 0.01));
    expect(approval.lastReason, contains('damaged packaging'));
    expect(details?.discountApprovalToken, 'TOKEN-1');
  });
}
