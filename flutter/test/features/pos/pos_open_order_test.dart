// Phase 7 F2 (decision 19 #1-#4): an order is rung at the till like a resumed
// held cart, but the prices are the order's (read-only), the quantities are
// capped at what is LEFT on each line, and the delivery fee the customer agreed
// is charged once - on the first fulfilment - and cannot be edited or re-booked.
//
// The contract pinned here is the money and the refusals:
//
//   * The cart charges the ORDER's line price, not today's catalogue price.
//   * A line cannot be rung above its remaining quantity.
//   * The first fulfilment shows the order's delivery fee, not editable, with no
//     Deliver toggle and no new discount (the approval was spent when the order
//     was saved).
//   * A refusal (short stock, no shift, over-remaining) keeps the cart, because
//     `fulfil_sales_order` runs in one transaction and wrote nothing.

import 'package:client/data/models/customer.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/models/sale_discount.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/repositories/customer_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/pos/widgets/pos_open_order_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import '../../support/phase4_fakes.dart';

/// A CONFIRMED order: cement 10 bags at 250 (catalogue says 270), PVC 5 pc at
/// 90 (catalogue says 95). Only 4 bags are on the shelf, so line 1 is short.
PosOpenOrder _confirmedOrder() => const PosOpenOrder(
  id: 7,
  number: 'ORD-20261113-0001',
  customerId: 3,
  status: 'CONFIRMED',
  lines: [
    PosOpenOrderLine(
      id: 71,
      variantUomId: 1,
      qty: 10,
      unitPrice: 250,
      remainingQty: 10,
      availableQty: 4,
      fulfilledQty: 0,
    ),
    PosOpenOrderLine(
      id: 72,
      variantUomId: 2,
      qty: 5,
      unitPrice: 90,
      remainingQty: 5,
      availableQty: 40,
      fulfilledQty: 0,
    ),
  ],
);

/// The same order after a first fulfilment: 4 bags and 5 pipes already rung.
PosOpenOrder _partialOrder() => const PosOpenOrder(
  id: 7,
  number: 'ORD-20261113-0001',
  customerId: 3,
  status: 'PARTIAL',
  lines: [
    PosOpenOrderLine(
      id: 71,
      variantUomId: 1,
      qty: 10,
      unitPrice: 250,
      remainingQty: 6,
      availableQty: 40,
      fulfilledQty: 4,
    ),
    PosOpenOrderLine(
      id: 72,
      variantUomId: 2,
      qty: 5,
      unitPrice: 90,
      remainingQty: 0,
      availableQty: 40,
      fulfilledQty: 5,
    ),
  ],
);

class _FakeOrderService extends PosService {
  _FakeOrderService() : super();

  List<PosOpenOrder> orders = const [];
  double? fee = 120;
  PosServiceException? failure;
  PosCheckoutResult? result;

  int fulfilCalls = 0;
  int? sentOrderId;
  List<PosFulfilLine> sentLines = const [];
  List<PosCheckoutPayment> sentPayments = const [];
  String? sentKey;

  @override
  Future<List<PosOpenOrder>> fetchOpenOrders() async => orders;

  @override
  Future<double?> fetchOrderDeliveryFee(int orderId) async => fee;

  @override
  Future<PosCheckoutResult> fulfilOrder({
    required int orderId,
    required List<PosFulfilLine> lines,
    required List<PosCheckoutPayment> payments,
    String? idempotencyKey,
  }) async {
    fulfilCalls++;
    sentOrderId = orderId;
    sentLines = lines;
    sentPayments = payments;
    sentKey = idempotencyKey;
    final boom = failure;
    if (boom != null) throw boom;
    return result ??
        PosCheckoutResult(
          id: 9,
          transactionNo: 'TRX-20261113-0009',
          orNumber: 'OR-20261113-0009',
          transDate: DateTime(2026, 11, 13, 10, 15),
          grandTotal: 2950,
          deliveryFee: fee ?? 0,
        );
  }
}

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
    DeliveryDraft? delivery,
  }) async => throw StateError('a fulfilment must not be rung as a checkout');
}

/// The till reads the customer list (to name the order's buyer) and that
/// customer's utang when an order is loaded; both are stubbed so a widget test
/// never needs a live transport.
class _StubCustomers extends CustomerService {
  @override
  Future<List<Customer>> fetchCustomers() async => const [
    Customer(id: 3, name: 'Maria Santos', customerType: 'REGULAR'),
  ];

  @override
  Future<CustomerLedgerSummary> fetchLedgerSummary(int customerId) async =>
      CustomerLedgerSummary.empty(customerId, name: 'Maria Santos');
}

class _OpenShift extends ShiftService {
  @override
  Future<Shift?> fetchCurrent() async => Shift(
    id: 1,
    cashierName: 'Ana Cruz',
    status: Shift.openStatus,
    openingFloat: 5000,
    closingCount: null,
    openedAt: DateTime(2026, 11, 13, 8),
    closedAt: null,
    notes: '',
    zReading: null,
  );
}

void main() {
  late InventoryViewmodel inventory;

  setUp(() => inventory = seededInventory());

  /// The till at 760px: the cart is a bar under the products, and the POS
  /// actions live in the header.
  Future<void> pumpTill(
    WidgetTester tester,
    PosTransactionViewmodel cart,
  ) async {
    tester.view.physicalSize = const Size(760, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: AuthViewmodel(AuthRepository(AuthService())),
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ],
          child: MaterialApp(
            home: PosTransactionPage(
              viewmodel: cart,
              shiftViewmodel: ShiftViewmodel(service: _OpenShift()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('only CONFIRMED and PARTIAL orders are open at the till', () {
    PosOpenOrder withStatus(String status) => PosOpenOrder.fromJson({
      'id': 1,
      'order_no': 'ORD-1',
      'customer': 2,
      'status': status,
      'items': [
        {
          'id': 11,
          'variant_uom': 1,
          'qty': '2.00',
          'unit_price': '250.00',
          'fulfilled_qty': status == 'PARTIAL' ? '1.00' : '0.00',
          'cancelled_qty': '0.00',
          'remaining_qty': status == 'PARTIAL' ? '1.00' : '2.00',
          'available_qty': '10.00',
        },
      ],
    });

    expect(withStatus('CONFIRMED').isOpen, isTrue);
    expect(withStatus('PARTIAL').isOpen, isTrue);
    expect(withStatus('COMPLETED').isOpen, isFalse);
    expect(withStatus('CANCELLED').isOpen, isFalse);
  });

  testWidgets('the open-order dialog lists the lines, prices and stock hint', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    PosOpenOrder? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await showDialog<PosOpenOrder>(
                  context: context,
                  builder: (_) => PosOpenOrderDialog(
                    orders: [_confirmedOrder()],
                    customerName: (_) => 'Maria Santos',
                    productName: (id) => switch (id) {
                      1 => 'Portland Cement 40kg',
                      2 => 'PVC Pipe 1/2 inch',
                      _ => 'Line $id',
                    },
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

    expect(find.textContaining('ORD-20261113-0001'), findsOneWidget);
    expect(find.textContaining('Maria Santos'), findsOneWidget);
    // Status reads as words, not wire codes.
    expect(find.textContaining('Partial'), findsNothing);
    expect(find.textContaining('Confirmed'), findsOneWidget);
    // Prices come from the ORDER, not from the catalogue behind the counter.
    expect(find.textContaining('250.00'), findsOneWidget);
    expect(find.textContaining('90.00'), findsOneWidget);
    // Per line: sellable stock in that line's unit versus what is still owed.
    expect(find.textContaining('Short by 6'), findsOneWidget);
    expect(find.textContaining('Enough in stock'), findsOneWidget);

    await tester.tap(find.text('Ring this order'));
    await tester.pumpAndSettle();
    expect(chosen?.id, 7);
  });

  testWidgets('opening an order loads its remaining lines at the order prices', (
    tester,
  ) async {
    final service = _FakeOrderService()..orders = [_confirmedOrder()];
    final cart = PosTransactionViewmodel(
      inventory,
      pos: _StubPosRepository(),
      orderService: service,
      customers: CustomerRepository(_StubCustomers()),
    );
    await pumpTill(tester, cart);

    await tester.tap(find.byKey(const ValueKey('pos-open-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ring this order'));
    await tester.pumpAndSettle();

    expect(cart.lines, hasLength(2));
    expect(cart.lines.first.quantity, 10);
    // Read-only price: the order's 250, not the catalogue's 270.
    expect(cart.lines.first.unitPrice, 250);
    expect(cart.lines.last.unitPrice, 90);
    expect(cart.isFulfillingOrder, isTrue);
    // Nothing rung yet, so this fulfilment carries the agreed delivery charge.
    expect(cart.orderDeliveryFee, 120);

    // Capped at what is still owed on the line.
    final refusal = cart.stepLine(0, 1);
    expect(refusal, isNotNull);
    expect(cart.lines.first.quantity, 10);
    // Editable DOWN to zero (a line the customer no longer wants is not rung).
    expect(cart.stepLine(0, -1), isNull);
    expect(cart.lines.first.quantity, 9);
  });

  testWidgets(
    'the first fulfilment shows the fee, with no toggle and no discount',
    (tester) async {
      final service = _FakeOrderService()..orders = [_confirmedOrder()];
      final cart = PosTransactionViewmodel(
        inventory,
        pos: _StubPosRepository(),
        orderService: service,
        customers: CustomerRepository(_StubCustomers()),
      );
      await pumpTill(tester, cart);

      await tester.tap(find.byKey(const ValueKey('pos-open-order')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ring this order'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Delivery charge'), findsOneWidget);
      expect(find.textContaining('120.00'), findsWidgets);
      // The trip was agreed with the order: it is not re-booked at the till.
      expect(find.text('Deliver to the customer'), findsNothing);
      expect(find.byKey(const ValueKey('pos-deliver-toggle')), findsNothing);
      // No new discount either - the approval was spent when the order was saved.
      expect(find.text('Apply a discount'), findsNothing);

      await tester.tap(find.text('Complete sale'));
      await tester.pumpAndSettle();

      expect(service.fulfilCalls, 1);
      expect(service.sentOrderId, 7);
      expect([for (final l in service.sentLines) l.orderLineId], [71, 72]);
      expect([for (final l in service.sentLines) l.quantity], [10, 5]);
      // One key for this attempt, so a dropped response cannot ring it twice.
      expect(service.sentKey, isNotNull);
      expect(service.sentKey, hasLength(32));
      // The sale is written: the cart is cleared and the order is left behind.
      expect(cart.lines, isEmpty);
      expect(cart.isFulfillingOrder, isFalse);
    },
  );

  testWidgets('a later fulfilment carries no fee', (tester) async {
    final service = _FakeOrderService()..orders = [_partialOrder()];
    final cart = PosTransactionViewmodel(
      inventory,
      pos: _StubPosRepository(),
      orderService: service,
      customers: CustomerRepository(_StubCustomers()),
    );
    await pumpTill(tester, cart);

    await tester.tap(find.byKey(const ValueKey('pos-open-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ring this order'));
    await tester.pumpAndSettle();

    // Only the bags are left; the pipes are done.
    expect(cart.lines, hasLength(1));
    expect(cart.lines.first.quantity, 6);
    // The fee was charged on the first fulfilment, so it is not owed again.
    expect(cart.orderDeliveryFee, 0);

    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Delivery charge'), findsNothing);
    expect(find.byKey(const ValueKey('pos-deliver-toggle')), findsNothing);
  });

  testWidgets('a refused fulfilment keeps the order in the cart', (
    tester,
  ) async {
    final service = _FakeOrderService()
      ..orders = [_confirmedOrder()]
      ..failure = const PosServiceException(
        'There is not enough stock to ring this order.',
        code: 'INSUFFICIENT_STOCK',
        variantId: 1,
      );
    final cart = PosTransactionViewmodel(
      inventory,
      pos: _StubPosRepository(),
      orderService: service,
      customers: CustomerRepository(_StubCustomers()),
    );
    await pumpTill(tester, cart);

    await tester.tap(find.byKey(const ValueKey('pos-open-order')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ring this order'));
    await tester.pumpAndSettle();
    // Let "Order loaded" clear: a ScaffoldMessenger QUEUES messages, so a refusal
    // shown next would otherwise sit behind a notice the cashier already read.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    expect(cart.submitError, contains('not enough stock'));
    expect(cart.submitErrorCode, 'INSUFFICIENT_STOCK');
    // Nothing was written, so the cashier corrects the basket and retries.
    expect(cart.lines, hasLength(2));
    expect(cart.isFulfillingOrder, isTrue);
    // The "Order loaded" notice has to clear before the refusal can be read: a
    // ScaffoldMessenger QUEUES messages rather than replacing them.
    expect(find.textContaining('not enough stock'), findsOneWidget);
  });
}
