import 'package:client/data/models/held_cart.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parked-cart queue (Phase 3).
///
/// A held cart is a basket the cashier walked away from. The rules that matter
/// are below the widget: a FAILED reload must not wipe the list (an empty parked
/// queue reads as "nothing was held", so a cashier would re-ring a basket that is
/// still parked), and a failed VOID must keep its row (the basket is still there
/// on the server, so hiding it would strand it).
class _StubHeldCarts extends HeldCartService {
  int fetchCalls = 0;
  final List<int> voided = [];
  final List<int> completed = [];
  Object? failFetch;
  Object? failVoid;
  Object? failComplete;
  Object? failHold;
  List<HeldCart> carts = const [];
  HeldCart? held;
  Map<String, dynamic> completedSale = const {'id': 77};

  @override
  Future<List<HeldCart>> fetchAll() async {
    fetchCalls++;
    if (failFetch != null) throw failFetch!;
    return carts;
  }

  @override
  Future<void> voidCart(int cartId) async {
    if (failVoid != null) throw failVoid!;
    voided.add(cartId);
  }

  @override
  Future<HeldCart> hold({
    int? customerId,
    String notes = '',
    required List<HeldCartItem> items,
  }) async {
    if (failHold != null) throw failHold!;
    return held!;
  }

  @override
  Future<Map<String, dynamic>> complete(
    int cartId, {
    required List<PosCheckoutPayment> payments,
  }) async {
    if (failComplete != null) throw failComplete!;
    completed.add(cartId);
    return completedSale;
  }
}

HeldCart _cart(int id, {String? customerName, String notes = ''}) {
  return HeldCart(
    id: id,
    customerId: customerName == null ? null : 10 + id,
    customerName: customerName,
    cashierName: 'Ana Cruz',
    notes: notes,
    items: [HeldCartItem(id: id * 10, variantUom: 5, qty: 2, unitPrice: 99.5)],
    createdAt: DateTime(2026, 10, 20, 9),
  );
}

void main() {
  group('HeldCartViewmodel.load', () {
    test('fills the queue from the service', () async {
      final service = _StubHeldCarts()
        ..carts = [_cart(1, customerName: 'Dela Cruz Construction')];
      final vm = HeldCartViewmodel(service: service);

      await vm.load();

      expect(service.fetchCalls, 1);
      expect(vm.carts, hasLength(1));
      expect(vm.carts.single.customerName, 'Dela Cruz Construction');
      expect(vm.isLoading, isFalse);
      expect(vm.loadError, isNull);
    });

    test('a failed reload KEEPS the carts it already had', () async {
      final service = _StubHeldCarts()
        ..carts = [_cart(1, customerName: 'Dela Cruz Construction')];
      final vm = HeldCartViewmodel(service: service);
      await vm.load();

      service.failFetch = const HeldCartServiceException('Cannot connect.');
      await vm.load();

      expect(
        vm.carts,
        hasLength(1),
        reason:
            'a blank queue reads as "nothing was held", so the cashier would '
            're-ring a basket that is still parked',
      );
      expect(vm.loadError, 'Cannot connect.');
      expect(vm.isLoading, isFalse);
    });

    test('a retry that succeeds clears the previous error', () async {
      final service = _StubHeldCarts()
        ..failFetch = const HeldCartServiceException('Cannot connect.');
      final vm = HeldCartViewmodel(service: service);
      await vm.load();
      expect(vm.loadError, isNotNull);

      service
        ..failFetch = null
        ..carts = [_cart(2)];
      await vm.load();

      expect(vm.loadError, isNull);
      expect(vm.carts, hasLength(1));
    });
  });

  group('HeldCartViewmodel.voidCart', () {
    test('removes the row only after the server accepts', () async {
      final service = _StubHeldCarts()..carts = [_cart(1), _cart(2)];
      final vm = HeldCartViewmodel(service: service);
      await vm.load();

      final ok = await vm.voidCart(1);

      expect(ok, isTrue);
      expect(service.voided, [1]);
      expect(vm.carts.map((c) => c.id), [2]);
    });

    test('a failed void KEEPS the row and reports why', () async {
      final service = _StubHeldCarts()
        ..carts = [_cart(1), _cart(2)]
        ..failVoid = const HeldCartServiceException(
          'The cart is already gone.',
        );
      final vm = HeldCartViewmodel(service: service);
      await vm.load();

      final ok = await vm.voidCart(1);

      expect(ok, isFalse);
      expect(
        vm.carts,
        hasLength(2),
        reason: 'the basket is still on the server, so hiding it strands it',
      );
      expect(vm.actionError, 'The cart is already gone.');
    });
  });

  group('HeldCartViewmodel.holdCart', () {
    test('puts the newly held cart at the top of the queue', () async {
      final service = _StubHeldCarts()
        ..carts = [_cart(1)]
        ..held = _cart(9, customerName: 'Maria Santos');
      final vm = HeldCartViewmodel(service: service);
      await vm.load();

      final held = await vm.holdCart(
        notes: 'pay tomorrow',
        items: const [
          HeldCartItem(id: 0, variantUom: 5, qty: 1, unitPrice: 99.5),
        ],
      );

      expect(held?.id, 9);
      expect(vm.carts.first.id, 9);
      expect(vm.carts, hasLength(2));
    });
  });

  group('HeldCartViewmodel.completeCart', () {
    test('drops the cart from the queue once the sale is written', () async {
      final service = _StubHeldCarts()..carts = [_cart(1), _cart(2)];
      final vm = HeldCartViewmodel(service: service);
      await vm.load();

      final sale = await vm.completeCart(
        1,
        payments: const [
          PosCheckoutPayment(method: 'CASH', amountTendered: 199),
        ],
      );

      expect(sale?['id'], 77);
      expect(service.completed, [1]);
      expect(vm.carts.map((c) => c.id), [2]);
    });
  });

  group('HeldCartViewmodel resume hand-off', () {
    test('resumeCart records the basket the till must pick up', () {
      final vm = HeldCartViewmodel(service: _StubHeldCarts());
      var notified = 0;
      vm.addListener(() => notified++);

      vm.resumeCart(_cart(7, customerName: 'Maria Santos'));

      expect(vm.pendingResume?.id, 7);
      expect(notified, 1, reason: 'the tab shows the hand-off as it happens');
    });

    test('takePendingResume CONSUMES it, so a rebuild cannot re-load it', () {
      final vm = HeldCartViewmodel(service: _StubHeldCarts());
      vm.resumeCart(_cart(7));

      expect(vm.takePendingResume()?.id, 7);
      expect(
        vm.pendingResume,
        isNull,
        reason:
            'a basket left pending would be re-filled into the till after the '
            'cashier had already paid for it',
      );
      expect(vm.takePendingResume(), isNull);
    });

    test('there is no pending basket until something is resumed', () {
      final vm = HeldCartViewmodel(service: _StubHeldCarts());
      expect(vm.pendingResume, isNull);
      expect(vm.takePendingResume(), isNull);
    });
  });
}
