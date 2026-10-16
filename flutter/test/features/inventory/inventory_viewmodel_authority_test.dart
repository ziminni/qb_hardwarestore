// Phase 2 (decision 13): the server is the SINGLE authority for inventory state.
//
// Two rules from decision 13 live here and are the reason this file exists:
//   1. the low-stock predicate must be the SERVER's — `total < threshold` with a
//      `threshold > 0` guard — not the client's old `stock <= threshold`. If the
//      list and the alert screen disagree on the boundary, the app contradicts
//      itself in front of the user.
//   2. movements come from `/api/v1/adjustments/`, not from a log the client
//      invents. (Ledger ruling: the local log is RETAINED but narrowed to the
//      movement kinds the API cannot supply — POS sales and opening stock —
//      because deleting it wholesale would make a demo sale produce no row at
//      all.)

import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({required int variantId, required double threshold}) =>
    Product(
      id: 6,
      categoryId: 3,
      categoryName: 'Electrical',
      brandId: 1,
      brandName: 'Omni',
      baseName: 'Circuit Breaker',
      description: '',
      imageUrl: '',
      isActive: true,
      variants: [
        ProductVariant(
          productId: 6,
          baseUomId: 2,
          maxStockLevel: 0,
          id: variantId,
          variantName: '20A 1-pole',
          baseUomCode: 'PC',
          isActive: true,
          minStockThreshold: threshold,
          sellingUoms: [
            VariantUom(
              id: variantId,
              variantId: variantId,
              uomId: 2,
              uomCode: 'PC',
              uomName: 'Piece',
              barcodeQr: '',
              conversionFactor: 1,
              defaultSellingPrice: 315,
            ),
          ],
        ),
      ],
    );

InventoryBatch _batch({required int variantId, required double qty}) =>
    InventoryBatch(
      id: variantId,
      variantId: variantId,
      receiptId: variantId,
      initialQty: qty,
      currentQty: qty,
      unitCostLanded: 180,
      markupPercentage: 0,
      batchSellingPrice: 180,
      expirationDate: null,
      createdAt: null,
    );

ProductsSnapshot _catalogue({double threshold = 20, double qty = 100}) =>
    ProductsSnapshot(
      products: [_product(variantId: 8, threshold: threshold)],
      batches: [_batch(variantId: 8, qty: qty)],
    );

StockAdjustment _adjustment({int id = 1, double qty = -3}) => StockAdjustment(
  id: id,
  variantId: 8,
  userId: 1,
  adjustmentType: StockAdjustmentType.shrinkage,
  quantityAdjusted: qty,
  remarks: 'Broken in transit.',
  timestamp: DateTime(2026, 9),
);

class _FakeProductsRepository extends ProductsRepository {
  _FakeProductsRepository(this.snapshot) : super(ProductsService());

  ProductsSnapshot snapshot;

  /// Counted so a test can prove the write path RE-READ rather than patching
  /// locally.
  int loadCalls = 0;

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    loadCalls++;
    return snapshot;
  }
}

/// One recorded call to the write path.
typedef _Recorded = ({
  int variantId,
  StockAdjustmentType type,
  double quantity,
  String remarks,
});

class _FakeInventoryRepository extends InventoryRepository {
  _FakeInventoryRepository() : super(InventoryService());

  List<SystemAlert> alerts = [];
  List<StockAdjustment> adjustments = [];
  InventoryServiceException? error;

  /// What the viewmodel asked the server to do. The tests assert against THIS
  /// rather than against the client's own batch arithmetic, because the client no
  /// longer performs the adjustment — the server does.
  final List<_Recorded> recorded = [];

  @override
  Future<List<SystemAlert>> loadAlerts() async {
    final failure = error;
    if (failure != null) throw failure;
    return alerts;
  }

  @override
  Future<List<StockAdjustment>> loadAdjustments() async {
    final failure = error;
    if (failure != null) throw failure;
    return adjustments;
  }

  @override
  Future<StockAdjustment> recordAdjustment({
    required int variantId,
    required StockAdjustmentType type,
    required double quantity,
    String remarks = '',
  }) async {
    final failure = error;
    if (failure != null) throw failure;
    recorded.add((
      variantId: variantId,
      type: type,
      quantity: quantity,
      remarks: remarks,
    ));
    return StockAdjustment(
      id: 99,
      variantId: variantId,
      userId: 1,
      adjustmentType: type,
      quantityAdjusted: quantity,
      remarks: remarks,
      timestamp: DateTime(2026, 10),
    );
  }
}

void main() {
  late _FakeProductsRepository products;
  late _FakeInventoryRepository inventory;

  setUp(() {
    products = _FakeProductsRepository(_catalogue());
    inventory = _FakeInventoryRepository();
  });

  InventoryViewmodel store() =>
      InventoryViewmodel(products: products, inventory: inventory);

  group('the server is the authority for inventory state', () {
    test(
      'load() brings alerts and adjustments in with the catalogue',
      () async {
        inventory.alerts = [
          const SystemAlert(
            id: 1,
            type: SystemAlertType.lowStock,
            variantId: 8,
            message: 'Low.',
            isResolved: false,
            createdAt: null,
          ),
        ];
        inventory.adjustments = [_adjustment()];

        final vm = store();
        expect(vm.alerts, isEmpty, reason: 'nothing loaded yet');

        await vm.load();

        expect(vm.alerts, hasLength(1));
        expect(vm.alerts.single.type, SystemAlertType.lowStock);
        expect(vm.adjustments, hasLength(1));
        expect(vm.adjustments.single.quantityAdjusted, -3);
      },
    );

    test('a failed load surfaces and does not wipe the loaded state', () async {
      inventory.adjustments = [_adjustment()];
      final vm = store();
      await vm.load();
      expect(vm.adjustments, hasLength(1));

      inventory.error = const InventoryServiceException('Cannot connect.');
      await vm.load();

      expect(vm.loadError, 'Cannot connect.');
      expect(
        vm.adjustments,
        hasLength(1),
        reason: 'an emptied list reads as "no adjustments", which is a lie',
      );
    });
  });

  group('the derived status matches the SERVER predicate exactly', () {
    test('a variant exactly AT its threshold is in stock, not low', () async {
      // The whole point of the alignment. Backend _check_low_stock uses
      // `total < threshold`, so a variant sitting on its threshold raises no
      // alert. If this returns lowStock the list and the alert screen disagree
      // about the same row.
      products.snapshot = _catalogue(threshold: 20, qty: 20);
      final vm = store();
      await vm.load();

      expect(vm.statusForVariant(8), InventoryStockStatus.inStock);
    });

    test('one unit BELOW the threshold is low', () async {
      products.snapshot = _catalogue(threshold: 20, qty: 19);
      final vm = store();
      await vm.load();

      expect(vm.statusForVariant(8), InventoryStockStatus.lowStock);
    });

    test('a zero threshold never produces a low reading', () async {
      // Backend guards with `threshold > 0`, so a 0 threshold means "not
      // tracked", not "everything is low".
      products.snapshot = _catalogue(threshold: 0, qty: 5);
      final vm = store();
      await vm.load();

      expect(vm.statusForVariant(8), InventoryStockStatus.inStock);
    });

    test('no stock at all is out of stock regardless of threshold', () async {
      products.snapshot = _catalogue(threshold: 0, qty: 0);
      final vm = store();
      await vm.load();

      expect(vm.statusForVariant(8), InventoryStockStatus.outOfStock);
    });
  });

  group('movements come from the server', () {
    test('the server adjustment appears as a movement row', () async {
      inventory.adjustments = [_adjustment(id: 7, qty: -3)];
      final vm = store();
      await vm.load();

      final rows = vm.movementsForVariant(8);
      expect(rows, isNotEmpty);
      expect(
        rows.first.quantityChange,
        -3,
        reason: 'the delta is the server\'s, not invented by the client',
      );
    });
  });

  // Decision 13: an adjustment is a WRITE to the server, not a local mutation. These
  // tests assert the request the client sends, because that is the only part the
  // client still owns. The client-side FIFO adjustment tests that used to live in
  // inventory_viewmodel_test.dart were deleted rather than left passing: they encoded
  // exactly the behaviour this decision removes. `sellStock` still deducts locally
  // and keeps its own FIFO coverage.
  group('adjustStock writes to the server, then re-reads', () {
    // The mock's variant 1 is replaced by the API catalogue in load(), so the
    // baseline is variant 8 at 100 units.
    test('POSTs the signed delta and the mapped adjustment type', () async {
      final vm = store();
      await vm.load();

      final ok = await vm.adjustStock(
        variantId: 8,
        newQuantity: 90,
        reason: 'Shrinkage / Loss',
        notes: 'Pallet was short.',
      );

      expect(ok, isTrue);
      expect(inventory.recorded, hasLength(1));
      final sent = inventory.recorded.single;
      expect(sent.variantId, 8);
      expect(sent.quantity, -10, reason: 'the delta, not the new count');
      expect(sent.type, StockAdjustmentType.shrinkage);
      expect(sent.remarks, 'Shrinkage / Loss — Pallet was short.');
    });

    test(
      're-reads after the write, because the server moved the stock',
      () async {
        final vm = store();
        await vm.load();
        final before = products.loadCalls;

        await vm.adjustStock(
          variantId: 8,
          newQuantity: 90,
          reason: 'Count Correction',
          notes: '',
        );

        expect(
          products.loadCalls,
          greaterThan(before),
          reason:
              'a client that only re-fetched adjustments would show the new '
              'movement beside a stale stock figure',
        );
      },
    );

    test('sends nothing when the count did not change', () async {
      final vm = store();
      await vm.load();

      final ok = await vm.adjustStock(
        variantId: 8,
        newQuantity: 100,
        reason: 'Count Correction',
        notes: '',
      );

      expect(ok, isTrue);
      expect(inventory.recorded, isEmpty);
    });

    test(
      'clamps a negative count instead of asking to remove more than exists',
      () async {
        final vm = store();
        await vm.load();

        await vm.adjustStock(
          variantId: 8,
          newQuantity: -50,
          reason: 'Count Correction',
          notes: '',
        );

        expect(
          inventory.recorded.single.quantity,
          -100,
          reason: 'clamped to 0, so the delta is -100 and not -150',
        );
      },
    );

    test(
      'a failed write reports failure rather than claiming success',
      () async {
        final vm = store();
        await vm.load();
        inventory.error = InventoryServiceException('Server unavailable.');

        final ok = await vm.adjustStock(
          variantId: 8,
          newQuantity: 90,
          reason: 'Count Correction',
          notes: '',
        );

        expect(ok, isFalse);
        expect(vm.loadError, 'Server unavailable.');
      },
    );
  });
}
