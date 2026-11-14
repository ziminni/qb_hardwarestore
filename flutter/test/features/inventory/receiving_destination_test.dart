// Phase 9 F2 (decision 21 §7 + plan Design 7): a delivery line goes to the
// product's HOME shelf unless the receiver says otherwise, so the request must
// carry the chosen shelf and nothing at all when it is the default.
//
// The server reads an omitted `location` as the product's `stored_at` — sending
// it explicitly would claim a choice nobody made — so the test pins BOTH: a
// picked shelf travels as `location`, an untouched one is absent.

import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/stock_on_hand.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/receiving_viewmodel.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_receiving_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

class _CapturingInventoryService extends InventoryService {
  _CapturingInventoryService() : super();

  /// Every payload `POST /goods-receipts/` was given, so a test asserts the
  /// WIRE and not the widget's internal state.
  final List<List<ReceiptLine>> recorded = [];

  /// Refusals to hand out before accepting, so a test can drive a FAILED
  /// submission and check what the screen still holds.
  int refuseNext = 0;

  @override
  Future<List<PurchaseOrderRecord>> fetchPurchaseOrders() async => const [
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
    if (refuseNext > 0) {
      refuseNext--;
      throw const InventoryServiceException('That shelf cannot take it.');
    }
    recorded.add(items);
    return GoodsReceiptRecord(
      id: 5,
      poId: poId,
      deliveryReceiptNo: deliveryReceiptNo,
      batches: const <InventoryBatch>[],
    );
  }
}

/// Stock in the Store only: the Store is variant 8's HOME shelf (the server's
/// `is_home`), so it is what the picker opens on.
InventoryViewmodel _catalogue() => InventoryViewmodel.seeded(
  products: [product(id: 8, storedAtId: 1)],
  locations: const [
    StorageLocation(id: 1, name: 'Store'),
    StorageLocation(id: 2, name: 'Bodega'),
    StorageLocation(id: 3, name: 'Closed shelf', isActive: false),
  ],
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

/// The product's home shelf has been DEACTIVATED and one active shelf is left:
/// the server's default (the home) is now a shelf this delivery cannot land on.
InventoryViewmodel _inactiveHomeCatalogue() => InventoryViewmodel.seeded(
  products: [product(id: 8, storedAtId: 1)],
  locations: const [
    StorageLocation(id: 1, name: 'Store', isActive: false),
    StorageLocation(id: 2, name: 'Bodega'),
  ],
  stockOnHand: const [
    StockOnHand(
      variantId: 8,
      locationId: 1,
      locationName: 'Store',
      locationActive: false,
      isHome: true,
      qty: 5,
    ),
  ],
);

/// No active shelf at all: nowhere a delivery can be recorded.
InventoryViewmodel _closedShopCatalogue() => InventoryViewmodel.seeded(
  products: [product(id: 8, storedAtId: 1)],
  locations: const [StorageLocation(id: 1, name: 'Store', isActive: false)],
  stockOnHand: const [
    StockOnHand(
      variantId: 8,
      locationId: 1,
      locationName: 'Store',
      locationActive: false,
      isHome: true,
      qty: 5,
    ),
  ],
);

Future<_CapturingInventoryService> _pumpReceipt(
  WidgetTester tester, {
  InventoryViewmodel? catalogue,
  bool submit = true,
  Future<void> Function(WidgetTester)? act,
}) async {
  tester.view.physicalSize = const Size(1600, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final service = _CapturingInventoryService();
  final receiving = ReceivingViewmodel(service: service);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<InventoryViewmodel>.value(
          value: catalogue ?? _catalogue(),
        ),
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: AuthViewmodel(AuthRepository(AuthService())),
        ),
      ],
      // The PAGE is pumped, not the workspace: it owns the first load and the
      // frame around the steps, exactly as the app runs it.
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
  testWidgets('the receiver can send a line to the Bodega', (tester) async {
    final service = await _pumpReceipt(
      tester,
      act: (tester) async {
        await tester.tap(find.byKey(const Key('receiving-destination-11')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bodega').last);
        await tester.pumpAndSettle();
      },
    );

    expect(service.recorded, hasLength(1));
    expect(service.recorded.single.single.locationId, 2);
  });

  testWidgets('an untouched line sends no location: the home shelf is the '
      'server\'s default, not a choice the clerk made', (tester) async {
    final service = await _pumpReceipt(tester);

    expect(service.recorded, hasLength(1));
    expect(service.recorded.single.single.locationId, isNull);
  });

  testWidgets('a deactivated shelf is not offered as a destination', (
    tester,
  ) async {
    await _pumpReceipt(
      tester,
      act: (tester) async {
        await tester.tap(find.byKey(const Key('receiving-destination-11')));
        await tester.pumpAndSettle();
        expect(
          find.text('Closed shelf'),
          findsNothing,
          reason: 'the server refuses a delivery into a deactivated location',
        );
      },
    );
  });

  testWidgets('an inactive home shelf still offers the one active shelf, and '
      'the receipt records there', (tester) async {
    // The server applies the product's HOME to a line with no `location`, and
    // refuses a delivery into a deactivated shelf: with the home deactivated the
    // only way out is picking the shelf that is left, so the picker must show
    // even though there is a single active destination.
    final service = await _pumpReceipt(
      tester,
      catalogue: _inactiveHomeCatalogue(),
      act: (tester) async {
        expect(
          find.byKey(const Key('receiving-destination-11')),
          findsOneWidget,
          reason: 'the default home is deactivated, so a choice is required',
        );
        await tester.tap(find.byKey(const Key('receiving-destination-11')));
        await tester.pumpAndSettle();
        expect(find.text('Store'), findsNothing);
        await tester.tap(find.text('Bodega').last);
        await tester.pumpAndSettle();
      },
    );

    expect(service.recorded, hasLength(1));
    expect(service.recorded.single.single.locationId, 2);
  });

  testWidgets('with no active shelf the receipt is refused on screen, not '
      'silently sent', (tester) async {
    final service = await _pumpReceipt(
      tester,
      catalogue: _closedShopCatalogue(),
      submit: false,
    );

    expect(
      find.byKey(const Key('receiving-no-active-location')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Record receipt'),
          )
          .onPressed,
      isNull,
      reason:
          'the server refuses every destination, so the button must not '
          'promise a receipt it cannot record',
    );
    expect(service.recorded, isEmpty);
  });

  testWidgets('a single shelf that IS the home stays a silent default', (
    tester,
  ) async {
    final service = await _pumpReceipt(
      tester,
      catalogue: InventoryViewmodel.seeded(
        products: [product(id: 8, storedAtId: 2)],
        locations: const [StorageLocation(id: 2, name: 'Bodega')],
      ),
      act: (tester) async {
        expect(find.byKey(const Key('receiving-destination-11')), findsNothing);
      },
    );

    expect(service.recorded.single.single.locationId, isNull);
  });

  testWidgets('a failed submission keeps the picked shelf for the retry', (
    tester,
  ) async {
    final service = await _pumpReceipt(
      tester,
      submit: false,
      act: (tester) async {
        await tester.tap(find.byKey(const Key('receiving-destination-11')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bodega').last);
        await tester.pumpAndSettle();
      },
    );
    service.refuseNext = 1;

    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();
    expect(service.recorded, isEmpty);

    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();
    expect(service.recorded, hasLength(1));
    expect(service.recorded.single.single.locationId, 2);
  });

  test('the request body omits a default and carries a chosen shelf', () {
    expect(const ReceiptLine(poItemId: 11, qty: 4).toJson(), {
      'po_item': 11,
      'qty': 4.0,
    });
    expect(const ReceiptLine(poItemId: 11, qty: 4, locationId: 2).toJson(), {
      'po_item': 11,
      'qty': 4.0,
      'location': 2,
    });
  });
}
