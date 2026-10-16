// Step 3 of the staged ProductVariant swap: stock moves onto batches.
//
// Ruling R12: the mock mirrors the backend's implemented behaviour, verified in
// `backend_django/apps/inventory/services.py`:
//   - `allocate_fifo` deducts OLDEST batch first, ordered by receipt date.
//   - `apply_stock_adjustment` sends removals through FIFO and lands additions on
//     the NEWEST active batch.
//
// Decision 10 answer: adding a product creates an opening batch, because the
// form collects a quantity and a cost and a batch is exactly "a lot at a cost".

import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Current quantities of a variant's batches, oldest receipt first.
List<double> _batchQtys(InventoryViewmodel vm, int variantId) =>
    vm.batchesFor(variantId).map((batch) => batch.currentQty).toList();

void main() {
  // Needed only by the location-hint group, which legitimately exercises
  // `shared_preferences` through its mock. The stock and lookup groups build a
  // viewmodel with no platform dependency at all.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InventoryViewmodel — stock lives on batches', () {
    test('stockOnHandFor sums every batch of a variant', () {
      // Variant 1 ("40 kg Bag") is seeded as two lots of the same delivery
      // series: 80 + 50 = the 130 the legacy field also carries.
      expect(InventoryViewmodel().stockOnHandFor(1), 130.0);
    });

    test('batches are exposed oldest receipt first', () {
      final vm = InventoryViewmodel();

      expect(vm.batchesFor(1).map((batch) => batch.receiptId).toList(), [1, 2]);
    });

    test('the catalogue carries batch stock and the selling-uom price', () {
      final row = InventoryViewmodel().catalogue.firstWhere(
        (item) => item.variant.id == 1,
      );

      expect(row.price, 270.0); // VariantUom.defaultSellingPrice
      expect(row.stockOnHand, 130.0); // summed batches
      expect(row.uom.barcodeQr, 'MAT-00001');
    });

    test('a sale deducts the oldest batch first', () {
      final vm = InventoryViewmodel();

      vm.sellStock(
        variantId: 1,
        quantity: 30,
        reference: 'SALE-1',
        userName: 'Test',
      );

      expect(_batchQtys(vm, 1), [50.0, 50.0]); // 80 - 30; newer lot untouched
      expect(vm.stockOnHandFor(1), 100.0);
    });

    test('a sale crossing a batch boundary drains the oldest batch first', () {
      final vm = InventoryViewmodel();

      vm.sellStock(
        variantId: 1,
        quantity: 100,
        reference: 'SALE-2',
        userName: 'Test',
      );

      expect(_batchQtys(vm, 1), [0.0, 30.0]);
      expect(vm.stockOnHandFor(1), 30.0);
    });

    test('a sale of more than is on hand changes nothing', () {
      final vm = InventoryViewmodel();

      vm.sellStock(
        variantId: 1,
        quantity: 999,
        reference: 'SALE-3',
        userName: 'Test',
      );

      expect(_batchQtys(vm, 1), [80.0, 50.0]);
      expect(vm.stockOnHandFor(1), 130.0);
    });

    test('a sale records the batch-derived before and after', () {
      final vm = InventoryViewmodel();

      vm.sellStock(
        variantId: 1,
        quantity: 30,
        reference: 'SALE-4',
        userName: 'Test',
      );

      final movement = vm.movements.firstWhere(
        (entry) => entry.reference == 'SALE-4',
      );
      expect(movement.previousStock, 130.0);
      expect(movement.newStock, 100.0);
      expect(movement.quantityChange, -30.0);
    });

    test('a downward count correction deducts oldest first', () {
      final vm = InventoryViewmodel();

      vm.adjustStock(
        variantId: 1,
        newQuantity: 120, // a delta of -10
        reason: 'Shrinkage',
        notes: '',
        userName: 'Test',
      );

      expect(_batchQtys(vm, 1), [70.0, 50.0]);
    });

    test('an upward count correction lands on the newest batch', () {
      final vm = InventoryViewmodel();

      vm.adjustStock(
        variantId: 1,
        newQuantity: 140, // a delta of +10
        reason: 'Return',
        notes: '',
        userName: 'Test',
      );

      expect(_batchQtys(vm, 1), [
        80.0,
        60.0,
      ]); // newest lot grew, oldest did not
      expect(vm.stockOnHandFor(1), 140.0);
    });

    test('adding a product records the opening stock it is given', () {
      final vm = InventoryViewmodel();
      const product = Product(
        id: 0,
        categoryId: 1,
        categoryName: 'Cement',
        brandId: 1,
        brandName: 'Holcim',
        baseName: 'Test Product',
        description: '',
        imageUrl: '',
        isActive: true,
        variants: [
          ProductVariant(
            id: 900,
            productId: 0,
            baseUomId: 1,
            minStockThreshold: 10,
            maxStockLevel: 0,
            variantName: 'Test Variant',
            baseUomCode: 'Bag',
            isActive: true,
            sellingUoms: [
              VariantUom(
                id: 900,
                variantId: 900,
                uomId: 1,
                uomCode: 'Bag',
                uomName: 'Bag',
                barcodeQr: '',
                conversionFactor: 1,
                defaultSellingPrice: 120,
              ),
            ],
          ),
        ],
      );

      // Stock arrives as batches, because a batch is exactly "a lot at a cost"
      // and the variant no longer owns a quantity (decision 02 / decision 10).
      vm.addProduct(
        product,
        openingStock: const [
          InventoryBatch(
            id: 0,
            variantId: 900,
            receiptId: 0,
            initialQty: 42,
            currentQty: 42,
            unitCostLanded: 100,
            markupPercentage: 0,
            batchSellingPrice: 120,
            expirationDate: null,
            createdAt: null,
          ),
        ],
      );

      final batches = vm.batchesFor(900);
      expect(batches, hasLength(1));
      expect(batches.single.currentQty, 42.0);
      expect(batches.single.unitCostLanded, 100.0);
      expect(batches.single.initialQty, 42.0);
      expect(vm.stockOnHandFor(900), 42.0);
      // The viewmodel assigns real ids rather than trusting the form's zeros.
      expect(batches.single.id, greaterThan(0));
      expect(batches.single.receiptId, greaterThan(0));
    });

    test('adding a product with no opening stock creates no batch', () {
      final vm = InventoryViewmodel();
      const product = Product(
        id: 0,
        categoryId: 1,
        categoryName: 'Cement',
        brandId: 1,
        brandName: 'Holcim',
        baseName: 'Zero Stock Product',
        description: '',
        imageUrl: '',
        isActive: true,
        variants: [
          ProductVariant(
            id: 901,
            productId: 0,
            baseUomId: 1,
            minStockThreshold: 10,
            maxStockLevel: 0,
            variantName: 'No Stock Variant',
            baseUomCode: 'Bag',
            isActive: true,
          ),
        ],
      );

      vm.addProduct(product);

      expect(vm.batchesFor(901), isEmpty);
      expect(vm.stockOnHandFor(901), 0.0);
      expect(vm.movements.where((m) => m.variantId == 901), isEmpty);
    });
  });

  // The three lookups the readers need once they stop reading the legacy
  // flattened fields. Each has exactly one home: barcode on the selling unit,
  // price on the selling unit (decision 08), cost on the newest batch.
  group('InventoryViewmodel — legacy field lookups', () {
    test('barcodeFor reads the selling uom, not a SKU', () {
      // There is no SKU field anywhere in the backend (decision 10);
      // VariantUom.barcodeQr is the only identifier the API carries.
      final vm = InventoryViewmodel();

      expect(vm.barcodeFor(1), 'MAT-00001');
    });

    test('barcodeFor is empty when no selling unit carries one', () {
      final vm = InventoryViewmodel();

      expect(vm.barcodeFor(999999), '');
    });

    test('priceFor reads the selling uom default, never a batch price', () {
      final vm = InventoryViewmodel();

      expect(vm.priceFor(1), 270.0); // uom price; batch price is also 270 here
      expect(vm.priceFor(999999), isNull);
    });

    test('costFor reads the newest batch, labelled as such', () {
      final vm = InventoryViewmodel();

      expect(vm.costFor(1), 235.0);
      expect(vm.costFor(999999), isNull);
    });

    test('costFor follows the newest batch, not the oldest', () {
      final vm = InventoryViewmodel();

      // An addition lands on the newest batch, which is the one cost reads.
      vm.adjustStock(
        variantId: 1,
        newQuantity: 140,
        reason: 'Return',
        notes: '',
        userName: 'Test',
      );

      expect(vm.costFor(1), 235.0);
      expect(vm.latestBatchFor(1)!.currentQty, 60.0);
    });

    test('variantFor finds a variant across products', () {
      final vm = InventoryViewmodel();

      expect(vm.variantFor(1)?.variantName, '40 kg Bag');
      expect(vm.variantFor(999999), isNull);
    });
  });

  // Storage location is store-local knowledge, not API data (decision 10). The
  // viewmodel owns it so widgets stay synchronous and the blob is read once
  // rather than once per table row.
  group('InventoryViewmodel — location hints', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('starts with no hints recorded', () async {
      final vm = InventoryViewmodel();

      expect(vm.locationHints, isEmpty);
      expect(vm.locationHintFor(1), '');
    });

    test('a saved hint is readable and survives a new viewmodel', () async {
      final vm = InventoryViewmodel();

      await vm.setLocationHint(1, 'Rack A-01');
      expect(vm.locationHintFor(1), 'Rack A-01');

      // A fresh viewmodel reads the same persisted blob.
      final reopened = InventoryViewmodel();
      await reopened.loadLocationHints();
      expect(reopened.locationHintFor(1), 'Rack A-01');
    });

    test('hints are keyed by variant, not product', () async {
      final vm = InventoryViewmodel();

      await vm.setLocationHint(1, 'Rack A-01');
      await vm.setLocationHint(2, 'Yard E-02');

      expect(vm.locationHintFor(1), 'Rack A-01');
      expect(vm.locationHintFor(2), 'Yard E-02');
    });

    test('an empty hint reads back as no hint', () async {
      final vm = InventoryViewmodel();
      await vm.setLocationHint(1, 'Rack A-01');

      await vm.setLocationHint(1, '   ');

      expect(vm.locationHintFor(1), '');
      expect(vm.locationHints, isEmpty);
    });

    test('setting a hint notifies listeners', () async {
      final vm = InventoryViewmodel();
      var notified = 0;
      vm.addListener(() => notified++);

      await vm.setLocationHint(1, 'Rack A-01');

      expect(notified, greaterThan(0));
    });
  });

  // Status must be derived from the batch total, not from the mirrored legacy
  // field, or step 4 could not delete that field.
  group('InventoryViewmodel — status from batch stock', () {
    test('a variant at or below its threshold is low stock', () {
      final vm = InventoryViewmodel();

      // Variant 1 holds 130 against a threshold of 30.
      expect(vm.statusForVariant(1), InventoryStockStatus.inStock);

      vm.sellStock(
        variantId: 1,
        quantity: 105,
        reference: 'SALE-LOW',
        userName: 'Test',
      );

      expect(vm.stockOnHandFor(1), 25.0);
      expect(vm.statusForVariant(1), InventoryStockStatus.lowStock);
    });

    test('an empty variant is out of stock', () {
      final vm = InventoryViewmodel();

      vm.sellStock(
        variantId: 1,
        quantity: 130,
        reference: 'SALE-ALL',
        userName: 'Test',
      );

      expect(vm.statusForVariant(1), InventoryStockStatus.outOfStock);
    });

    test('an unknown variant is out of stock, not a crash', () {
      expect(
        InventoryViewmodel().statusForVariant(999999),
        InventoryStockStatus.outOfStock,
      );
    });
  });

  group('InventoryViewmodel — adjustment edge cases', () {
    const noStockProduct = Product(
      id: 0,
      categoryId: 1,
      categoryName: 'Cement',
      brandId: 1,
      brandName: 'Holcim',
      baseName: 'Zero Stock Product',
      description: '',
      imageUrl: '',
      isActive: true,
      variants: [
        ProductVariant(
          id: 901,
          productId: 0,
          baseUomId: 1,
          minStockThreshold: 10,
          maxStockLevel: 0,
          variantName: 'No Stock Variant',
          baseUomCode: 'Bag',
          isActive: true,
        ),
      ],
    );

    test('a correction below zero is clamped instead of draining stock', () {
      // The dialog validates >= 0, but a programmatic caller can pass a negative
      // "new quantity". Clamping keeps the recorded movement honest: without it
      // the movement would report a NEGATIVE newStock.
      final vm = InventoryViewmodel();

      vm.adjustStock(
        variantId: 1,
        newQuantity: -50,
        reason: 'Bad input',
        notes: '',
        userName: 'Test',
      );

      expect(vm.stockOnHandFor(1), 0.0);
      final movement = vm.movements.firstWhere(
        (entry) => entry.type == InventoryMovementType.stockAdjustment,
      );
      expect(movement.newStock, 0.0);
      expect(movement.newStock, greaterThanOrEqualTo(0));
      expect(movement.previousStock, 130.0);
    });

    test('an upward correction on a variant with no batches records it', () {
      // DELIBERATE DIVERGENCE from the backend, recorded rather than hidden:
      // `apply_stock_adjustment` (backend_django/apps/inventory/services.py)
      // applies NOTHING when no batch has current_qty > 0, so a correction on a
      // fully-depleted item is silently discarded. That is arguably a backend
      // bug, and silently losing a count the user just typed would be a visible
      // defect in the demo this mock exists to drive.
      //
      // So the count is honoured and the new lot carries it at zero cost, because
      // there is no cost basis to know. Raised to the human partner as a possible
      // backend bug; fixing the backend is out of this client-only map's scope.
      final vm = InventoryViewmodel();
      vm.addProduct(noStockProduct);
      expect(vm.batchesFor(901), isEmpty);

      vm.adjustStock(
        variantId: 901,
        newQuantity: 40,
        reason: 'Opening count',
        notes: '',
        userName: 'Test',
      );

      expect(vm.stockOnHandFor(901), 40.0);
      expect(vm.batchesFor(901), hasLength(1));
      expect(vm.batchesFor(901).single.unitCostLanded, 0.0);
    });

    test('a correction that changes nothing records no movement', () {
      final vm = InventoryViewmodel();
      final before = vm.movements.length;

      vm.adjustStock(
        variantId: 1,
        newQuantity: 130,
        reason: 'No change',
        notes: '',
        userName: 'Test',
      );

      expect(vm.movements, hasLength(before));
    });

    test('selling an unknown variant is a no-op, not a crash', () {
      final vm = InventoryViewmodel();

      vm.sellStock(
        variantId: 999999,
        quantity: 1,
        reference: 'SALE-X',
        userName: 'Test',
      );

      expect(vm.movements.any((m) => m.reference == 'SALE-X'), isFalse);
    });
  });
}
