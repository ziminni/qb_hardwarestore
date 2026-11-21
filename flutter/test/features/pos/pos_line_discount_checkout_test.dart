// The till's half of a LINE discount: the cart's own arithmetic, the approval
// percent it reports, and what goes on the wire.
//
// The server takes the line discount off that line first and measures the sale
// discount, the cap and the manager approval on what is left, so a till that
// previews the two separately shows a total nobody is charged and asks for an
// approval the server would have demanded sooner.

import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/held_cart.dart';
import 'package:client/data/models/sale_discount.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

class _RecordingPosRepository extends PosRepository {
  _RecordingPosRepository() : super(PosService());

  List<PosCheckoutItem> lastItems = const [];
  PosDiscount? lastDiscount;

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
    DeliveryDraft? delivery,
    bool creditSale = false,
  }) async {
    lastItems = items;
    lastDiscount = discount;
    return PosCheckoutResult(
      id: 7,
      transactionNo: 'TRX-20261120-0007',
      orNumber: 'OR-20261120-0007',
      transDate: DateTime(2026, 11, 20, 10),
      grandTotal: 500,
    );
  }
}

class _RecordingHeldCarts extends HeldCartService {
  final List<int> completes = [];
  final List<int> voids = [];

  @override
  Future<Map<String, dynamic>> complete(
    int cartId, {
    required List<PosCheckoutPayment> payments,
    String? idempotencyKey,
    PosDiscount? discount,
    String? discountApproval,
    DeliveryDraft? delivery,
    bool creditSale = false,
  }) async {
    completes.add(cartId);
    return {
      'id': 19,
      'transaction_no': 'TRX-19',
      'trans_date': '2026-11-20T11:30:00Z',
      'grand_total': '540.00',
      'receipt': {'or_number': 'OR-19'},
      'items': const <Map<String, dynamic>>[],
    };
  }

  @override
  Future<void> voidCart(int cartId) async => voids.add(cartId);
}

void main() {
  late InventoryViewmodel inventory;
  late _RecordingPosRepository repository;
  late _RecordingHeldCarts heldCarts;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = seededInventory();
    repository = _RecordingPosRepository();
    heldCarts = _RecordingHeldCarts();
    cart = PosTransactionViewmodel(
      inventory,
      pos: repository,
      heldCarts: heldCarts,
    );
  });

  /// Two bags of the first product (270 each = 540).
  void addTwo() {
    final option = cart.saleOptionsFor(cart.filteredProducts.first).first;
    expect(cart.addLine(option, 2), isNull);
  }

  const offForty = PosDiscount(
    kind: DiscountKind.amount,
    value: 40,
    reason: 'chipped bag',
  );

  group('the cart line', () {
    test('carries a discount and reports the discounted line', () {
      addTwo();
      expect(cart.subtotal, 540);
      expect(cart.total, 540);

      cart.setLineDiscount(0, offForty);

      expect(cart.lines.single.discount, offForty);
      expect(cart.lines.single.netTotal, 500);
      // The sale total the cashier reads is what the customer owes for the goods:
      // the line discounts are already off it.
      expect(cart.lineDiscountTotal, 40);
      expect(cart.total, 500);
      expect(cart.hasLineDiscount, isTrue);
    });

    test('a line discount can be taken back off', () {
      addTwo();
      cart.setLineDiscount(0, offForty);
      cart.setLineDiscount(0, null);

      expect(cart.lineDiscountTotal, 0);
      expect(cart.hasLineDiscount, isFalse);
      expect(cart.total, 540);
    });

    test('a discount on a removed line cannot outlive the line', () {
      addTwo();
      cart.setLineDiscount(0, offForty);
      cart.removeLine(0);

      expect(cart.lineDiscountTotal, 0);
      expect(cart.total, 0);
    });
  });

  group('the checkout body', () {
    test('sends the line discount on ITS line', () async {
      addTwo();
      cart.setLineDiscount(0, offForty);

      expect(await cart.submit(method: TenderMethod.cash, amountPaid: 500),
          isTrue);

      final body = repository.lastItems.single.toJson();
      expect(body['discount'], {
        'kind': 'AMOUNT',
        'value': '40.00',
        'reason': 'chipped bag',
      });
      // The sale-level discount is still its own, separate object.
      expect(repository.lastDiscount, isNull);
    });

    test('a line with no discount sends none', () async {
      addTwo();

      expect(await cart.submit(method: TenderMethod.cash, amountPaid: 540),
          isTrue);

      expect(repository.lastItems.single.toJson().containsKey('discount'),
          isFalse);
    });
  });

  group('a resumed parked cart', () {
    HeldCart parked() => HeldCart(
      id: 7,
      customerId: null,
      customerName: null,
      cashierName: 'Ana Cruz',
      notes: '',
      items: [
        HeldCartItem(
          id: 70,
          variantUom: cart.saleOptionsFor(cart.filteredProducts.first).first
              .variantUomId,
          qty: 2,
          unitPrice: 270,
        ),
      ],
      createdAt: DateTime(2026, 11, 20, 9),
    );

    test('an UNCHANGED basket still completes the parked cart', () async {
      cart.loadHeldCart(parked());

      expect(await cart.submit(method: TenderMethod.cash, amountPaid: 540),
          isTrue);

      expect(heldCarts.completes, [7], reason: 'decision 05');
    });

    test('a basket given a LINE discount is rung from the till instead', () async {
      cart.loadHeldCart(parked());
      cart.setLineDiscount(0, offForty);

      expect(await cart.submit(method: TenderMethod.cash, amountPaid: 500),
          isTrue);

      // `complete` sends no line discounts, so ringing through it would silently
      // give the customer a full-price sale. The till posts the sale itself and
      // voids the parked copy afterwards.
      expect(heldCarts.completes, isEmpty);
      expect(repository.lastItems.single.toJson()['discount'], isNotNull);
      expect(heldCarts.voids, [7]);
    });
  });
}
