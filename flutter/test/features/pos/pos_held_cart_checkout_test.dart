// C3 — a RESUMED held cart was checked out through POST /transactions/ and the parked
// cart was never removed, so the same basket could be resumed and sold a SECOND time.
//
// Decision 05 (planning/cashier-workflow/decisions/05-held-sale-model.md) and
// `HeldCartService` both say completion goes through POST /held-carts/{id}/complete/:
// the server runs `process_sale` and deletes the cart inside ONE transaction, and it
// honours `Idempotency-Key`, so a retry after a dropped response finds the sale instead
// of ringing a second one.
//
// The chosen shape (see the viewmodel's `submit`):
//
//   * resumed and UNCHANGED  -> complete/{id}: atomic, cannot double-sell, and the cart
//     cannot survive a successful sale.
//   * resumed and EDITED     -> POST /transactions/ (the server's copy is stale, so
//     completing it would sell what the cashier removed) and then DELETE the cart, only
//     after the sale is 201.
//   * not resumed            -> plain checkout, untouched.

import 'package:client/data/models/tender_method.dart';
import 'package:client/data/models/held_cart.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FakePosRepository extends PosRepository {
  _FakePosRepository() : super(PosService());

  int calls = 0;
  List<PosCheckoutPayment> sentPayments = const [];
  String? sentKey;

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
    sentKey = idempotencyKey;
    return PosCheckoutResult(
      id: 18,
      transactionNo: 'TRX-18',
      orNumber: 'OR-18',
      transDate: DateTime(2026, 10, 24, 11),
      grandTotal: 20,
    );
  }
}

class _FakeHeldCartService extends HeldCartService {
  final List<({int cartId, List<PosCheckoutPayment> payments, String? key})>
  completes = [];
  final List<int> voids = [];

  Object? failComplete;
  Object? failVoid;
  List<HeldCart> carts = const [];

  @override
  Future<List<HeldCart>> fetchAll() async => carts;

  @override
  Future<Map<String, dynamic>> complete(
    int cartId, {
    required List<PosCheckoutPayment> payments,
    String? idempotencyKey,
  }) async {
    completes.add((cartId: cartId, payments: payments, key: idempotencyKey));
    final boom = failComplete;
    if (boom != null) throw boom;
    return {
      'id': 19,
      'transaction_no': 'TRX-19',
      'trans_date': '2026-10-24T11:30:00Z',
      'grand_total': '20.00',
      'receipt': {'or_number': 'OR-19'},
      'items': const <Map<String, dynamic>>[],
    };
  }

  @override
  Future<void> voidCart(int cartId) async {
    voids.add(cartId);
    final boom = failVoid;
    if (boom != null) throw boom;
  }
}

/// The till is gated on an open shift, so the page test needs one or the pay
/// button never appears.
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

/// The till loads the live catalogue on open; these fail deterministically so no
/// test touches the network and the bundled rows stay the catalogue under test.
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

void main() {
  late InventoryViewmodel inventory;
  late _FakePosRepository pos;
  late _FakeHeldCartService heldService;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = InventoryViewmodel(
      products: _FailingProductsRepository(),
      inventory: _FailingInventoryRepository(),
    );
    pos = _FakePosRepository();
    heldService = _FakeHeldCartService();
    cart = PosTransactionViewmodel(
      inventory,
      ProductTrackingViewmodel(),
      pos: pos,
      heldCarts: heldService,
    );
  });

  /// Parks a basket on the server and resumes it into the till.
  HeldCart resumeOne({double qty = 2}) {
    final option = cart.saleOptionsFor(cart.filteredProducts.first).first;
    final held = HeldCart(
      id: 7,
      customerId: null,
      customerName: null,
      cashierName: 'Ana Cruz',
      notes: '',
      items: [
        HeldCartItem(
          id: 70,
          variantUom: option.variantUomId,
          qty: qty,
          unitPrice: option.unitPrice,
        ),
      ],
      createdAt: DateTime(2026, 10, 24, 9),
    );
    cart.loadHeldCart(held);
    return held;
  }

  /// Pays the basket. NO customer is selected, so the basket stays exactly what was
  /// resumed — selecting one would be an edit, and an edited basket takes the checkout
  /// path by design.
  Future<bool> submit() =>
      cart.submit(method: TenderMethod.cash, amountPaid: cart.total);

  test('an UNCHANGED resumed basket COMPLETES the parked cart', () async {
    resumeOne();
    expect(await submit(), isTrue);

    expect(heldService.completes, hasLength(1), reason: 'decision 05');
    expect(heldService.completes.single.cartId, 7);
    expect(
      pos.calls,
      0,
      reason:
          'POST /transactions/ would leave the parked cart behind - that is the '
          'double-sale defect',
    );
    expect(
      heldService.voids,
      isEmpty,
      reason: 'complete deletes the cart itself',
    );
    expect(
      cart.lines,
      isEmpty,
      reason: 'the sale is written, so the till frees up',
    );
    expect(cart.receipts.single.officialReceiptNumber, 'OR-19');
    expect(cart.receipts.single.paymentMethod, 'CASH');
  });

  test('the completion carries the tender and an idempotency key', () async {
    resumeOne();
    await submit();

    final sent = heldService.completes.single;
    expect(sent.payments.single.method, 'CASH');
    expect(
      sent.payments.single.amountTendered,
      cart.receipts.single.amountPaid,
    );
    expect(
      sent.key,
      isNotNull,
      reason:
          'a dropped response must be answerable by replaying the key, because the '
          'successful call deleted the cart',
    );
  });

  test(
    'a RETRY reuses the same key, so one basket cannot become two sales',
    () async {
      resumeOne();
      heldService.failComplete = const HeldCartServiceException(
        'Cannot connect to the BuildPro server.',
      );

      expect(await submit(), isFalse);
      expect(cart.submitError, isNotNull);
      expect(
        cart.lines,
        hasLength(1),
        reason: 'the cart is untouched on failure',
      );
      final firstKey = cart.idempotencyKey;

      heldService.failComplete = null;
      expect(await submit(), isTrue);

      expect(heldService.completes, hasLength(2));
      expect(heldService.completes.last.key, firstKey);
      expect(heldService.completes.last.cartId, 7);
    },
  );

  test('a FAILED completion keeps the cart AND the parked row', () async {
    resumeOne();
    heldService.failComplete = const HeldCartServiceException(
      'Cannot connect to the BuildPro server.',
    );

    expect(await submit(), isFalse);
    expect(pos.calls, 0);
    expect(heldService.voids, isEmpty);
    expect(cart.lines, hasLength(1), reason: 'the sale did not happen');
    expect(
      cart.completedHeldCartId,
      isNull,
      reason: 'nothing was sold, so the held list must keep showing the cart',
    );
  });

  test(
    'an EDITED resumed basket sells through checkout, then voids the cart',
    () async {
      resumeOne();
      // The cashier changes the parked basket: the server's copy is now stale, so
      // completing it would sell what they removed.
      final option = cart.saleOptionsFor(cart.filteredProducts.first).first;
      expect(cart.addLine(option, 1), isNull);

      expect(await submit(), isTrue);

      expect(
        pos.calls,
        1,
        reason: 'the edited basket is the one that must be sold',
      );
      expect(
        heldService.completes,
        isEmpty,
        reason: 'the parked copy is stale',
      );
      expect(heldService.voids, [
        7,
      ], reason: 'the cart must not survive the sale');
      expect(cart.completedHeldCartId, 7);
    },
  );

  test(
    'a plain (never resumed) basket never touches the held-cart API',
    () async {
      final option = cart.saleOptionsFor(cart.filteredProducts.first).first;
      expect(cart.addLine(option, 1), isNull);

      expect(await submit(), isTrue);

      expect(pos.calls, 1);
      expect(heldService.completes, isEmpty);
      expect(heldService.voids, isEmpty);
      expect(cart.completedHeldCartId, isNull);
    },
  );

  group(
    'the till REMOVES the completed cart from the Held transactions list',
    () {
      testWidgets('after a resumed sale the row is gone', (tester) async {
        tester.view.physicalSize = const Size(1600, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final option = cart.saleOptionsFor(cart.filteredProducts.first).first;
        final held = HeldCart(
          id: 7,
          customerId: null,
          customerName: null,
          cashierName: 'Ana Cruz',
          notes: '',
          items: [
            HeldCartItem(
              id: 70,
              variantUom: option.variantUomId,
              qty: 2,
              unitPrice: option.unitPrice,
            ),
          ],
          createdAt: DateTime(2026, 10, 24, 9),
        );
        heldService.carts = [held];
        final heldCarts = HeldCartViewmodel(service: heldService);
        await heldCarts.load();
        heldCarts.resumeCart(held);

        await tester.pumpWidget(
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: AuthViewmodel(AuthRepository(AuthService())),
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<InventoryViewmodel>.value(
                  value: inventory,
                ),
                ChangeNotifierProvider<ProductTrackingViewmodel>.value(
                  value: ProductTrackingViewmodel(),
                ),
              ],
              child: MaterialApp(
                home: PosTransactionPage(
                  viewmodel: cart,
                  shiftViewmodel: ShiftViewmodel(service: _OpenShift()),
                  heldCartViewmodel: heldCarts,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          cart.lines,
          hasLength(1),
          reason: 'the parked basket is in the till',
        );
        expect(heldCarts.carts, hasLength(1));

        await tester.tap(find.text('Proceed to payment'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Complete sale'));
        await tester.pumpAndSettle();

        expect(heldService.completes, hasLength(1));
        expect(
          heldCarts.carts,
          isEmpty,
          reason:
              'a cart the server no longer holds must not sit in the queue '
              'inviting a second resume',
        );
      });
    },
  );

  test('a sale made after a completed cart starts clean', () async {
    resumeOne();
    expect(await submit(), isTrue);

    final option = cart.saleOptionsFor(cart.filteredProducts.first).first;
    expect(cart.addLine(option, 1), isNull);
    expect(await submit(), isTrue);

    expect(pos.calls, 1, reason: 'the second basket was never parked');
    expect(heldService.completes, hasLength(1));
  });
}
