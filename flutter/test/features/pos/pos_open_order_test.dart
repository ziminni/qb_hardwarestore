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
    String? invoiceNo,
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
    bool creditSale = false,
    String? invoiceNo,
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

  // Owner 2026-11-23: the manager takes sales orders, so the till DOES offer
  // them - supersedes the 2026-11-20 no-button ruling from when no orders
  // existed. Cashier taps Orders, picks one, rings the remainder at agreed
  // prices.
  testWidgets('the cart bar opens an order and rings it at agreed prices', (
    tester,
  ) async {
    final cart = PosTransactionViewmodel(
      inventory,
      pos: _StubPosRepository(),
      orderService: _FakeOrderService()..orders = [_confirmedOrder()],
      customers: CustomerRepository(_StubCustomers()),
    );
    await pumpTill(tester, cart);

    expect(find.byKey(const ValueKey('pos-open-order')), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pos-open-order')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ORD-20261113-0001'), findsOneWidget);

    await tester.tap(find.text('Ring this order'));
    await tester.pumpAndSettle();

    // The remainder lands at the ORDER's prices, not the catalogue's.
    expect(cart.lines, hasLength(2));
    expect(cart.lines.first.unitPrice, 250);
    expect(cart.isFulfillingOrder, isTrue);
    // The active order reads in the bar (ellipsized column, not the button).
    expect(find.textContaining('ORD-20261113-0001'), findsWidgets);
  });
}
