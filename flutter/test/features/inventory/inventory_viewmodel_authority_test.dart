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

Product _product({required int variantId, required double threshold}) => Product(
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

ProductsSnapshot _catalogue({
  double threshold = 20,
  double qty = 100,
}) => ProductsSnapshot(
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

  @override
  Future<ProductsSnapshot> loadCatalogue() async => snapshot;
}

class _FakeInventoryRepository extends InventoryRepository {
  _FakeInventoryRepository() : super(InventoryService());

  List<SystemAlert> alerts = [];
  List<StockAdjustment> adjustments = [];
  InventoryServiceException? error;

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
    test('load() brings alerts and adjustments in with the catalogue', () async {
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
    });

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
}
