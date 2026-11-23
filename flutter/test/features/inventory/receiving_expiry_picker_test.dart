// Expiry tracking (reports-suite MAP, P2): the Expires date on a goods receipt
// line is OPTIONAL and only offered for a product that tracks expiry — cement and
// paint. A product that does not track expiry must show no field at all, and its
// line must not carry a date: absent means undated, never a fake far-future day.
//
// The label is the owner's wording, so it is pinned here.

import 'package:client/core/format/format.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/stock_on_hand.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/receiving_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_receiving_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

const _expiryLabel = 'Expiry (optional, cement/paint only)';

class _CapturingInventoryService extends InventoryService {
  _CapturingInventoryService({required this.tracksExpiry}) : super();

  /// Whether the one PO line's product tracks expiry, which is what the server
  /// says on the wire (`POItemSerializer.tracks_expiry`).
  final bool tracksExpiry;

  final List<List<ReceiptLine>> recorded = [];

  @override
  Future<List<PurchaseOrderRecord>> fetchPurchaseOrders() async => [
    PurchaseOrderRecord(
      id: 1,
      supplierId: 2,
      status: 'ORDERED',
      notes: '',
      items: [
        PurchaseOrderItem(
          id: 11,
          poId: 1,
          variantId: 8,
          variantName: 'Portland 40kg',
          orderedQty: 10,
          unitCost: 50,
          receivedQty: 0,
          unitCode: 'BAG',
          conversionFactor: 1,
          tracksExpiry: tracksExpiry,
        ),
      ],
    ),
  ];

  @override
  Future<List<GoodsReceiptRecord>> fetchGoodsReceipts() async => const [];

  @override
  Future<GoodsReceiptRecord> createReceipt({
    required int poId,
    required List<ReceiptLine> items,
    String deliveryReceiptNo = '',
  }) async {
    recorded.add(items);
    return GoodsReceiptRecord(
      id: 5,
      poId: poId,
      deliveryReceiptNo: deliveryReceiptNo,
      batches: const <InventoryBatch>[],
    );
  }
}

InventoryViewmodel _catalogue() => InventoryViewmodel.seeded(
  products: [product(id: 8, storedAtId: 1)],
  locations: const [StorageLocation(id: 1, name: 'Store')],
  stockOnHand: const [
    StockOnHand(
      variantId: 8,
      locationId: 1,
      locationName: 'Store',
      locationActive: true,
      isHome: true,
      qty: 5,
    ),
  ],
);

Future<_CapturingInventoryService> _pumpReceipt(
  WidgetTester tester, {
  required bool tracksExpiry,
  bool submit = true,
  Future<void> Function(WidgetTester)? act,
}) async {
  tester.view.physicalSize = const Size(1600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final service = _CapturingInventoryService(tracksExpiry: tracksExpiry);
  final receiving = ReceivingViewmodel(service: service);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<InventoryViewmodel>.value(value: _catalogue()),
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: AuthViewmodel(AuthRepository(AuthService())),
        ),
      ],
      child: MaterialApp(home: InventoryReceivingPage(viewmodel: receiving)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('receiving-order-1')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('receiving-qty-11')), '4');
  await tester.pumpAndSettle();
  if (act != null) await act(tester);
  if (submit) {
    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();
  }
  return service;
}

void main() {
  testWidgets('a product that does not track expiry offers no Expires field', (
    tester,
  ) async {
    final service = await _pumpReceipt(tester, tracksExpiry: false);

    expect(find.text(_expiryLabel), findsNothing);
    expect(find.byKey(const Key('receiving-expiry-11')), findsNothing);
    expect(service.recorded, hasLength(1));
    expect(service.recorded.single.single.expirationDate, isNull);
  });

  testWidgets('a product that tracks expiry offers the optional Expires date '
      'and sends the picked day', (tester) async {
    final today = appClock.now();
    final service = await _pumpReceipt(
      tester,
      tracksExpiry: true,
      act: (tester) async {
        expect(find.text(_expiryLabel), findsOneWidget);
        await tester.tap(find.byKey(const Key('receiving-expiry-11')));
        await tester.pumpAndSettle();
        // The calendar opens on today; today's own day cell is the pick.
        await tester.tap(find.text('${today.day}').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        // The chosen day is shown back to the clerk.
        expect(find.text(formatDate(today)), findsOneWidget);
      },
    );

    expect(service.recorded, hasLength(1));
    final picked = service.recorded.single.single.expirationDate;
    expect(picked, isNotNull);
    expect(formatDate(picked!.toLocal()), formatDate(today));
    expect(
      service.recorded.single.single.toJson()['expiration_date'],
      '${today.year.toString().padLeft(4, '0')}-'
      '${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}',
    );
  });

  testWidgets('an untouched Expires field is left off the wire entirely', (
    tester,
  ) async {
    final service = await _pumpReceipt(tester, tracksExpiry: true);

    expect(service.recorded, hasLength(1));
    expect(service.recorded.single.single.expirationDate, isNull);
    expect(
      service.recorded.single.single.toJson().containsKey('expiration_date'),
      isFalse,
    );
  });
}
