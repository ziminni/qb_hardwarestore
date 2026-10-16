// Phase 2 (decision 13): the server is the single authority for inventory state.
// This service is where that authority is reached.
//
// Payload shapes are trimmed copies of the REAL serializers, verified 2026-10-16:
//   SystemAlertSerializer     -> id, alert_type, variant, message, is_resolved, created_at
//   StockAdjustmentSerializer -> id, variant, user, adjustment_type, qty_adjusted, remarks, timestamp
//
// One test below exists purely as the decision-03 anti-regression: a body with no
// `results` list must THROW, not return an empty list. The lost PosService
// hand-rolled `data['results']`, which turns a contract break into a silent
// "nothing here" — the exact failure this project has already paid for once.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _alertsPath = '/api/v1/alerts/';
const _adjustmentsPath = '/api/v1/adjustments/';

Map<String, dynamic> _envelope(List<Map<String, dynamic>> results) => {
  'count': results.length,
  'next': null,
  'previous': null,
  'results': results,
};

Map<String, dynamic> _alert({
  int id = 1,
  String type = 'LOW_STOCK',
  bool resolved = false,
}) => {
  'id': id,
  'alert_type': type,
  'variant': 8,
  'message': 'Circuit Breaker 20A 1-pole is low on stock.',
  'is_resolved': resolved,
  'created_at': '2026-09-25T16:24:33.630104+08:00',
};

Map<String, dynamic> _adjustment({
  int id = 1,
  String type = 'SHRINKAGE',
  String qty = '-3.00',
}) => {
  'id': id,
  'variant': 8,
  'user': 1,
  'adjustment_type': type,
  'qty_adjusted': qty,
  'remarks': 'Broken in transit.',
  'timestamp': '2026-09-25T16:24:33.630104+08:00',
};

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.bodies, {this.statusCode = 200});

  final Map<String, Object?> bodies;
  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (!bodies.containsKey(options.path)) {
      return ResponseBody.fromString('{"detail":"not found"}', 404, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return ResponseBody.fromString(
      jsonEncode(bodies[options.path]),
      statusCode,
      headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient client;
  // `ApiClient.init()` assigns a `late final dio`, so it is NOT idempotent.
  setUpAll(() => client = ApiClient.instance..init());

  late _FakeAdapter adapter;

  void useBodies(Map<String, Object?> bodies, {int statusCode = 200}) {
    adapter = _FakeAdapter(bodies, statusCode: statusCode);
    client.dio.httpClientAdapter = adapter;
  }

  InventoryService service() => InventoryService(client: client);

  group('InventoryService.fetchAlerts', () {
    test('loads alerts from the alerts endpoint', () async {
      useBodies({
        _alertsPath: _envelope([
          _alert(id: 1, type: 'LOW_STOCK'),
          _alert(id: 2, type: 'OUT_OF_STOCK'),
        ]),
      });

      final alerts = await service().fetchAlerts();

      expect(alerts, hasLength(2));
      expect(alerts.first.type, SystemAlertType.lowStock);
      expect(alerts.first.variantId, 8);
      expect(alerts.first.isResolved, isFalse);
      expect(alerts.first.message, contains('low on stock'));
      expect(alerts.last.type, SystemAlertType.outOfStock);
      expect(adapter.requests.single.path, _alertsPath);
    });

    test('keeps an unknown alert type rather than dropping the alert', () async {
      // A backend that adds an alert type must not make the screen silently
      // shorter. Unknown maps to a benign label, the row still renders.
      useBodies({
        _alertsPath: _envelope([_alert(type: 'SOMETHING_NEW')]),
      });

      final alerts = await service().fetchAlerts();

      expect(alerts, hasLength(1));
      expect(alerts.single.type, SystemAlertType.unknown);
    });

    test('a body with no results list throws instead of reading empty', () async {
      useBodies({
        _alertsPath: {'count': 1, 'next': null, 'previous': null},
      });

      await expectLater(
        service().fetchAlerts(),
        throwsA(isA<FormatException>()),
      );
    });

    test('a failed request becomes an InventoryServiceException', () async {
      useBodies({}, statusCode: 500);

      await expectLater(
        service().fetchAlerts(),
        throwsA(isA<InventoryServiceException>()),
      );
    });
  });

  group('InventoryService.fetchAdjustments', () {
    test('loads adjustments, keeping the delta sign', () async {
      useBodies({
        _adjustmentsPath: _envelope([
          _adjustment(id: 1, type: 'SHRINKAGE', qty: '-3.00'),
          _adjustment(id: 2, type: 'RETURN', qty: '12.00'),
        ]),
      });

      final rows = await service().fetchAdjustments();

      expect(rows, hasLength(2));
      expect(rows.first.adjustmentType, StockAdjustmentType.shrinkage);
      expect(
        rows.first.quantityAdjusted,
        -3,
        reason: 'a removal is negative, and the sign is the whole meaning',
      );
      expect(rows.last.adjustmentType, StockAdjustmentType.returnToSupplier);
      expect(rows.last.quantityAdjusted, 12);
      expect(adapter.requests.single.path, _adjustmentsPath);
    });
  });

  group('InventoryService.createAdjustment', () {
    test('POSTs the adjustment and returns the stored row', () async {
      useBodies({
        // NOT pre-encoded: the fake adapter encodes the body itself, so passing a
        // String here would double-encode it into a JSON string literal.
        // The type must match what is POSTed below, or this asserts the fixture
        // rather than the call.
        _adjustmentsPath: _adjustment(id: 9, type: 'DAMAGE', qty: '-2.00'),
      });

      final created = await service().createAdjustment(
        variantId: 8,
        type: StockAdjustmentType.damage,
        quantity: -2,
        remarks: 'Cracked casing.',
      );

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.path, _adjustmentsPath);
      expect(request.data, {
        'variant': 8,
        'adjustment_type': 'DAMAGE',
        'qty_adjusted': -2.0,
        'remarks': 'Cracked casing.',
      });
      expect(created.id, 9);
      expect(created.adjustmentType, StockAdjustmentType.damage);
    });
  });
}
