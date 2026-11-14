// Phase 9 F2 (decision 21 §8 / plan Design 8): an adjustment belongs to ONE
// shelf. The dialog counts that shelf, the request names it, and the money-side
// rule the server enforces — an inactive shelf can only LOSE stock — is said in
// the dialog instead of becoming a 400 at the counter.
//
// A dialog opened without the location list behaves exactly as it did before
// Phase 9 (one whole-shop count, no `location` on the wire).

import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/stock_on_hand.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_adjust_stock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

class _CapturingInventoryRepository extends FakeInventoryRepository {
  _CapturingInventoryRepository() : super();

  /// What the viewmodel asked the server to write, so the test asserts the WIRE
  /// (the `location` field) rather than the widget's state.
  final List<({int variantId, double quantity, int? locationId})> recorded = [];

  @override
  Future<StockAdjustment> recordAdjustment({
    required int variantId,
    required StockAdjustmentType type,
    required double quantity,
    String remarks = '',
    int? locationId,
  }) async {
    recorded.add((
      variantId: variantId,
      quantity: quantity,
      locationId: locationId,
    ));
    return StockAdjustment(
      id: 99,
      variantId: variantId,
      userId: 1,
      adjustmentType: type,
      quantityAdjusted: quantity,
      remarks: remarks,
      timestamp: DateTime(2026, 11, 14),
    );
  }
}

const _locations = [
  StorageLocation(id: 1, name: 'Store'),
  StorageLocation(id: 2, name: 'Bodega'),
  StorageLocation(id: 3, name: 'Closed shelf', isActive: false),
];

const _stockByLocation = [
  StockOnHand(
    variantId: 8,
    locationId: 1,
    locationName: 'Store',
    locationActive: true,
    isHome: true,
    qty: 10,
  ),
  StockOnHand(
    variantId: 8,
    locationId: 2,
    locationName: 'Bodega',
    locationActive: true,
    isHome: false,
    qty: 4,
  ),
  StockOnHand(
    variantId: 8,
    locationId: 3,
    locationName: 'Closed shelf',
    locationActive: false,
    isHome: false,
    qty: 2,
  ),
];

InventoryViewmodel _store(_CapturingInventoryRepository repository) =>
    InventoryViewmodel(
      // The on-hand rows are the server's: they are what says the Store holds 10
      // and the Bodega 4, so `load()` must bring them in like the app does.
      products: FakeProductsRepository(
        products: [product(id: 8)],
        stockOnHand: _stockByLocation,
      ),
      inventory: repository,
      catalogue: FakeCatalogueRepository(),
      storageLocations: FakeStorageLocationRepository(locations: _locations),
    );

Future<InventoryAdjustStockResult?> _openAndCount(
  WidgetTester tester,
  String locationLabel,
  String count,
) async {
  InventoryAdjustStockResult? result;
  final item = product(id: 8);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<InventoryAdjustStockResult>(
                context: context,
                builder: (_) => InventoryAdjustStockDialog(
                  product: item,
                  variant: item.variants.first,
                  currentStock: 16,
                  locations: _locations,
                  stockByLocation: _stockByLocation,
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

  await tester.tap(find.byKey(const Key('adjust-location')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(locationLabel).last);
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextFormField).first, count);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Confirm Adjustment'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  group('the dialog counts the shelf it is about', () {
    testWidgets('it opens on the product\'s home shelf', (tester) async {
      final item = product(id: 8);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryAdjustStockDialog(
              product: item,
              variant: item.variants.first,
              currentStock: 16,
              locations: _locations,
              stockByLocation: _stockByLocation,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('adjust-location')), findsOneWidget);
      // 10 PC on the home shelf, twice: the system box and the untouched field.
      expect(find.text('10  PC', findRichText: true), findsNWidgets(2));
    });

    testWidgets('picking the Bodega re-reads the count there', (tester) async {
      final item = product(id: 8);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: InventoryAdjustStockDialog(
              product: item,
              variant: item.variants.first,
              currentStock: 16,
              locations: _locations,
              stockByLocation: _stockByLocation,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('adjust-location')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bodega').last);
      await tester.pumpAndSettle();

      expect(find.text('4  PC', findRichText: true), findsNWidgets(2));
      expect(
        find.text('No change'),
        findsOneWidget,
        reason: 'the field starts at the shelf\'s own count, not the shop total',
      );
    });

    testWidgets('the confirmed count carries the shelf', (tester) async {
      InventoryAdjustStockResult? result;
      final item = product(id: 8);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<InventoryAdjustStockResult>(
                    context: context,
                    builder: (_) => InventoryAdjustStockDialog(
                      product: item,
                      variant: item.variants.first,
                      currentStock: 16,
                      locations: _locations,
                      stockByLocation: _stockByLocation,
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
      await tester.tap(find.byKey(const Key('adjust-location')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bodega').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, '6');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm Adjustment'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.quantity, 6);
      expect(result!.locationId, 2);
    });
  });

  group('the inactive shelf', () {
    testWidgets('may lose stock', (tester) async {
      final result = await _openAndCount(tester, 'Closed shelf (inactive)', '1');

      expect(result, isNotNull);
      expect(result!.locationId, 3);
      expect(result.quantity, 1);
    });

    testWidgets('may not gain stock, and the dialog says why', (tester) async {
      final result = await _openAndCount(tester, 'Closed shelf (inactive)', '5');

      expect(result, isNull, reason: 'the server refuses an addition there');
      expect(
        find.text(
          'Closed shelf is deactivated: stock can only be removed there.',
        ),
        findsOneWidget,
      );
    });
  });

  group('the request', () {
    test('names the shelf and counts the delta from ITS stock', () async {
      final repository = _CapturingInventoryRepository();
      final store = _store(repository);
      await store.load();

      final ok = await store.adjustStock(
        variantId: 8,
        newQuantity: 6,
        reason: 'Count Correction',
        notes: '',
        locationId: 2,
      );

      expect(ok, isTrue);
      expect(repository.recorded, hasLength(1));
      // The Bodega holds 4, so counting 6 there is +2 — not -10 against the shop.
      expect(repository.recorded.single.locationId, 2);
      expect(repository.recorded.single.quantity, 2);
    });

    test('a count without a shelf is the whole shop, as before', () async {
      final repository = _CapturingInventoryRepository();
      final store = _store(repository);
      await store.load();

      await store.adjustStock(
        variantId: 8,
        newQuantity: 12,
        reason: 'Count Correction',
        notes: '',
      );

      expect(repository.recorded.single.locationId, isNull);
    });
  });
}
