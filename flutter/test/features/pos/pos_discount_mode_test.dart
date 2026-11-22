import 'package:client/data/models/sale_discount.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_payment_dialog.dart';
import 'package:client/features/pos/widgets/pos_transaction_cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

class _CapturingPosRepository extends PosRepository {
  _CapturingPosRepository() : super(PosService());

  List<PosCheckoutItem> capturedItems = const [];
  PosDiscount? capturedDiscount;

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
  }) async {
    capturedItems = items;
    capturedDiscount = discount;
    return PosCheckoutResult(
      id: 1,
      transactionNo: 'TRX-1',
      orNumber: 'OS-1',
      transDate: DateTime(2026, 11, 22, 10),
      grandTotal: 290,
      discountAmount: 10,
      discountReason: discount?.reason ?? '',
    );
  }
}

void main() {
  test(
    'allocateWholeSaleDiscountShares splits proportionally over included lines',
    () {
      final shares = allocateWholeSaleDiscountShares(
        [
          (amount: 100, included: true),
          (amount: 200, included: false),
          (amount: 200, included: true),
        ],
        30,
      );
      expect(shares, [10.0, 0.0, 20.0]);
    },
  );

  test(
    'viewmodel enforces mutual exclusion and sends include_in_discount=false',
    () async {
      final repo = _CapturingPosRepository();
      final cart = PosTransactionViewmodel(seededInventory(), pos: repo);
      final products = cart.filteredProducts;
      expect(products.length, greaterThanOrEqualTo(2));
      expect(cart.addLine(cart.saleOptionsFor(products[0]).first, 1), isNull);
      expect(cart.addLine(cart.saleOptionsFor(products[1]).first, 1), isNull);

      // Per-line discount enabled.
      cart.setLineDiscount(
        1,
        const PosDiscount(
          kind: DiscountKind.amount,
          value: 10,
          reason: 'Torn bag',
        ),
      );
      expect(cart.hasLineDiscount, isTrue);

      // Whole-sale discount refused while a line discount is active.
      cart.setWholeSaleDiscount(
        const PosDiscount(
          kind: DiscountKind.percent,
          value: 10,
          reason: 'Promo',
        ),
      );
      expect(cart.hasWholeSaleDiscount, isFalse);

      // Clear line discount -> whole-sale discount is now allowed.
      cart.setLineDiscount(1, null);
      cart.setWholeSaleDiscount(
        const PosDiscount(
          kind: DiscountKind.percent,
          value: 10,
          reason: 'Promo',
        ),
      );
      expect(cart.hasWholeSaleDiscount, isTrue);

      // Line discount refused while whole-sale discount is active.
      cart.setLineDiscount(
        0,
        const PosDiscount(
          kind: DiscountKind.amount,
          value: 5,
          reason: 'Scratch',
        ),
      );
      expect(cart.hasLineDiscount, isFalse);

      // Untick line 1 from whole-sale discount.
      cart.setLineIncludedInDiscount(1, false);
      expect(cart.neverDiscountedTotal, cart.lines[1].total);

      final ok = await cart.submit(
        tenders: [
          PosCheckoutPayment(method: 'CASH', amountTendered: cart.total),
        ],
        discount: cart.wholeSaleDiscount,
      );
      expect(ok, isTrue);
      expect(repo.capturedItems.length, 2);
      expect(repo.capturedItems[0].includeInDiscount, isTrue);
      expect(
        repo.capturedItems[0].toJson().containsKey('include_in_discount'),
        isFalse,
      );
      expect(repo.capturedItems[1].includeInDiscount, isFalse);
      expect(repo.capturedItems[1].toJson()['include_in_discount'], isFalse);
    },
  );

  testWidgets(
    'cart disables line discount button and shows inclusion checkboxes when whole-sale discount is active',
    (tester) async {
      tester.view.physicalSize = const Size(760, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final cart = PosTransactionViewmodel(
        seededInventory(),
        pos: _CapturingPosRepository(),
      );
      final products = cart.filteredProducts;
      cart.addLine(cart.saleOptionsFor(products[0]).first, 1);
      cart.addLine(cart.saleOptionsFor(products[1]).first, 1);
      cart.setWholeSaleDiscount(
        const PosDiscount(
          kind: DiscountKind.percent,
          value: 10,
          reason: 'Promo',
        ),
      );

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

      final btn0 = tester.widget<IconButton>(
        find.byKey(const ValueKey('pos-line-discount-open-0')),
      );
      expect(btn0.onPressed, isNull);
      expect(
        find.byKey(const ValueKey('pos-cart-discount-include-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('pos-cart-discount-include-1')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'payment dialog disables whole-sale discount when line discounts are active',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final cart = PosTransactionViewmodel(
        seededInventory(),
        pos: _CapturingPosRepository(),
      );
      cart.addLine(cart.saleOptionsFor(cart.filteredProducts.first).first, 1);
      cart.setLineDiscount(
        0,
        const PosDiscount(
          kind: DiscountKind.amount,
          value: 5,
          reason: 'Damaged',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosPaymentDialog(
              total: cart.total,
              cart: cart,
              onSubmit: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final toggle = tester.widget<Switch>(
        find.byKey(const ValueKey('pos-discount-toggle')),
      );
      expect(toggle.onChanged, isNull);
      expect(
        find.textContaining('Per-product discounts are active'),
        findsOneWidget,
      );
    },
  );
}
