// The last link in the decision-06 section 3 chain, and the one that is easiest to
// leave out: the viewmodel knowing WHICH line is short is worth nothing unless the cart
// shows it. Leaving this off would repeat, one layer up, the exact defect the review
// found - a marker nothing reads.

import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_transaction_cart.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubPosRepository extends PosRepository {
  _StubPosRepository() : super(PosService());

  PosServiceException? failure;

  @override
  Future<int> walkInCustomerId() async => 1;

  @override
  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
  }) async {
    final boom = failure;
    if (boom != null) throw boom;
    return PosCheckoutResult(
      id: 18,
      transactionNo: 'TRX-20261016-0007',
      orNumber: 'OR-20261016-0007',
      transDate: DateTime(2026, 10, 16, 18, 56),
      grandTotal: 20,
    );
  }
}

void main() {
  late InventoryViewmodel inventory;
  late _StubPosRepository repository;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = InventoryViewmodel();
    repository = _StubPosRepository();
    cart = PosTransactionViewmodel(
      inventory,
      ProductTrackingViewmodel(),
      pos: repository,
    );
  });

  Future<void> pumpCart(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<PosTransactionViewmodel>.value(
        value: cart,
        child: MaterialApp(
          home: Scaffold(
            body: PosTransactionCart(
              onPayment: () {},
              onClear: () {},
              onChangeCustomer: () {},
            ),
          ),
        ),
      ),
    );
  }

  /// Puts two DIFFERENT variants in the cart and returns the first one's ids.
  ({int lineId, int variantId, String name}) addTwoLines() {
    final first = cart.filteredProducts.first;
    final firstOption = cart.saleOptionsFor(first).first;
    expect(cart.addLine(firstOption, 1), isNull);
    final second = cart.filteredProducts[1];
    final secondOption = cart.saleOptionsFor(second).first;
    expect(cart.addLine(secondOption, 1), isNull);
    return (
      lineId: firstOption.variantUomId,
      variantId: firstOption.variantId,
      name: firstOption.productName,
    );
  }

  testWidgets('the short line is marked, and the innocent one is not', (
    tester,
  ) async {
    final target = addTwoLines();
    final other = cart.lines.last.productName;
    repository.failure = PosServiceException(
      'Insufficient stock for ${target.name}.',
      code: 'INSUFFICIENT_STOCK',
      variantId: target.variantId,
    );
    await cart.submit(paymentMethod: 'CASH', amountPaid: 1);
    await pumpCart(tester);

    // Exactly one row carries the marker, and it is the right one.
    expect(
      find.textContaining('Not enough stock'),
      findsOneWidget,
      reason: 'the cashier must be able to see which row to fix',
    );
    final marked = tester.widget<ListTile>(
      find.ancestor(
        of: find.textContaining('Not enough stock'),
        matching: find.byType(ListTile),
      ),
    );
    expect((marked.title! as Text).data, target.name);
    expect(
      cart.lines.last.productName,
      isNot(target.name),
      reason: 'need two rows',
    );
    expect(cart.lines.last.productName, other);
  });

  testWidgets('no failure means no marker', (tester) async {
    addTwoLines();
    await pumpCart(tester);

    expect(find.textContaining('Not enough stock'), findsNothing);
  });

  testWidgets('a terminal failure marks nothing', (tester) async {
    addTwoLines();
    repository.failure = PosServiceException('The server broke.');
    await cart.submit(paymentMethod: 'CASH', amountPaid: 1);
    await pumpCart(tester);

    expect(
      find.textContaining('Not enough stock'),
      findsNothing,
      reason: 'a 500 is not a stock problem and must not accuse a row',
    );
  });
}
