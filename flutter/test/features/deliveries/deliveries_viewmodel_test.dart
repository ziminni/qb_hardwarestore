// Phase 5 F3 (decision 18): the delivery schedule's data.
//
// What is pinned here is what the screen cannot afford to get wrong:
//   * a refused move shows the SERVER's sentence, then re-reads the schedule, so
//     the buttons match the row the server actually holds;
//   * a second click while the first is in flight posts nothing (one slip, one
//     move);
//   * a failure without a reason is refused before any request, because the
//     server stores the reason on the row;
//   * a failed load keeps the rows it already had - "no deliveries" and "not
//     loaded" are different facts about the day.

import 'package:client/data/models/delivery.dart';
import 'package:client/data/services/delivery_service.dart';
import 'package:client/features/deliveries/viewmodels/deliveries_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

Delivery _delivery({
  int id = 1,
  String no = 'DLV-20261111-0001',
  DeliveryStatus status = DeliveryStatus.scheduled,
  DateTime? scheduledDate,
  double fee = 50,
  String customer = 'Maria Santos',
  String contact = 'Maria Santos',
  String address = '12 Mabini St, Cebu City',
}) => Delivery(
  id: id,
  deliveryNo: no,
  saleId: 9,
  salesOrderId: null,
  transactionNo: 'TRX-20261111-0009',
  orderNo: '',
  customerId: 3,
  customerName: customer,
  address: address,
  contactName: contact,
  contactPhone: '09171234567',
  scheduledDate: scheduledDate ?? DateTime(2026, 11, 12),
  fee: fee,
  status: status,
  failureReason: status == DeliveryStatus.failed ? 'Customer not home.' : '',
  items: const [DeliveryItem(name: 'Portland cement', unit: 'BAG', qty: 2)],
  createdByName: 'Maria Santos',
  createdAt: DateTime(2026, 11, 11, 9),
);

class _StubService extends DeliveryService {
  _StubService({List<Delivery>? deliveries})
    : deliveries = deliveries ?? [_delivery()];

  List<Delivery> deliveries;
  String? loadFailure;
  final List<String> calls = [];
  DeliveryServiceException? moveFailure;
  Delivery? moved;

  @override
  Future<List<Delivery>> fetchAll({
    DeliveryStatus? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    calls.add('load');
    if (loadFailure != null) throw DeliveryServiceException(loadFailure!);
    return deliveries;
  }

  @override
  Future<Delivery> start(int id) async {
    calls.add('start:$id');
    final boom = moveFailure;
    if (boom != null) throw boom;
    return moved ?? _delivery(id: id, status: DeliveryStatus.outForDelivery);
  }

  @override
  Future<Delivery> deliver(int id) async {
    calls.add('deliver:$id');
    final boom = moveFailure;
    if (boom != null) throw boom;
    return moved ?? _delivery(id: id, status: DeliveryStatus.delivered);
  }

  @override
  Future<Delivery> fail(int id, String reason) async {
    calls.add('fail:$id:$reason');
    final boom = moveFailure;
    if (boom != null) throw boom;
    return _delivery(id: id, status: DeliveryStatus.failed);
  }
}

void main() {
  test('load fills the rows; a later failure KEEPS them', () async {
    final service = _StubService();
    final viewmodel = DeliveriesViewmodel(service: service);

    await viewmodel.load();
    expect(viewmodel.deliveries, hasLength(1));
    expect(viewmodel.isLoading, isFalse);
    expect(viewmodel.loadError, isNull);

    service.loadFailure = 'Cannot connect to the BuildPro server.';
    await viewmodel.load();

    expect(
      viewmodel.deliveries,
      hasLength(1),
      reason: 'an empty list would read as "nothing to deliver today"',
    );
    expect(viewmodel.loadError, contains('Cannot connect'));
  });

  test('filtered() narrows by status, scheduled date and search', () async {
    final viewmodel = DeliveriesViewmodel(
      service: _StubService(
        deliveries: [
          _delivery(id: 1, no: 'DLV-1', scheduledDate: DateTime(2026, 11, 12)),
          _delivery(
            id: 2,
            no: 'DLV-2',
            status: DeliveryStatus.delivered,
            scheduledDate: DateTime(2026, 11, 10),
          ),
          _delivery(
            id: 3,
            no: 'DLV-3',
            customer: 'Cebu Steel Works',
            scheduledDate: DateTime(2026, 11, 20),
          ),
        ],
      ),
    );

    await viewmodel.load();

    expect(
      [
        for (final row in viewmodel.filtered(status: DeliveryStatus.delivered))
          row.id,
      ],
      [2],
    );
    expect(
      [
        for (final row in viewmodel.filtered(
          dateFrom: DateTime(2026, 11, 11),
          dateTo: DateTime(2026, 11, 13),
        ))
          row.id,
      ],
      [1],
    );
    expect([for (final row in viewmodel.filtered(query: 'steel')) row.id], [3]);
  });

  test('start replaces the row with the server\'s copy', () async {
    final service = _StubService(
      deliveries: [_delivery(id: 4, status: DeliveryStatus.scheduled)],
    );
    final viewmodel = DeliveriesViewmodel(service: service);
    await viewmodel.load();

    final moved = await viewmodel.start(4);

    expect(moved, isTrue);
    expect(viewmodel.deliveries.single.status, DeliveryStatus.outForDelivery);
    expect(service.calls, ['load', 'start:4']);
  });

  test(
    'a 409 refusal shows the server detail and re-reads the schedule',
    () async {
      final service = _StubService(
        deliveries: [_delivery(id: 4, status: DeliveryStatus.scheduled)],
      );
      final viewmodel = DeliveriesViewmodel(service: service);
      await viewmodel.load();

      service.moveFailure = const DeliveryServiceException(
        'Delivery DLV-20261111-0001 is DELIVERED and cannot move again.',
        code: 'DELIVERY_TRANSITION_INVALID',
        status: 'DELIVERED',
      );
      // The server now holds the delivered row; the re-read must pick it up.
      service.deliveries = [_delivery(id: 4, status: DeliveryStatus.delivered)];

      final moved = await viewmodel.deliver(4);

      expect(moved, isFalse);
      expect(
        viewmodel.actionError,
        contains('is DELIVERED and cannot move again'),
        reason: 'the server names the state; a canned sentence cannot',
      );
      expect(service.calls, ['load', 'deliver:4', 'load']);
      expect(
        viewmodel.deliveries.single.status,
        DeliveryStatus.delivered,
        reason: 'the buttons must follow the row the server holds',
      );
    },
  );

  test('a second click while a move is in flight posts nothing', () async {
    final service = _StubService();
    final viewmodel = DeliveriesViewmodel(service: service);
    await viewmodel.load();

    final first = viewmodel.start(1);
    final second = viewmodel.start(1);
    await Future.wait([first, second]);

    expect(
      service.calls.where((call) => call.startsWith('start')),
      hasLength(1),
      reason: 'one slip, one move: a double click must not post twice',
    );
  });

  test('a failure without a reason is refused before any request', () async {
    final service = _StubService();
    final viewmodel = DeliveriesViewmodel(service: service);
    await viewmodel.load();

    final moved = await viewmodel.fail(1, '   ');

    expect(moved, isFalse);
    expect(viewmodel.actionError, contains('needs a reason'));
    expect(
      service.calls.any((call) => call.startsWith('fail')),
      isFalse,
      reason: 'the server stores the reason on the row; it is not optional',
    );
  });

  test('a reason is trimmed and sent with the failure', () async {
    final service = _StubService();
    final viewmodel = DeliveriesViewmodel(service: service);
    await viewmodel.load();

    final moved = await viewmodel.fail(1, '  Customer not home.  ');

    expect(moved, isTrue);
    expect(service.calls, contains('fail:1:Customer not home.'));
    expect(viewmodel.deliveries.single.status, DeliveryStatus.failed);
  });
}
