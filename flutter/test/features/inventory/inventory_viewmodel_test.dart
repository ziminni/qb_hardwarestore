// The inventory store, after Phase 4 Task 4 removed its mock seed and its
// in-memory mutators (`addProduct`, `updateProduct`, `sellStock`, and the opening
// batches they wrote).
//
// The stock/batch assertions below are the SAME questions the file asked before —
// totals, FIFO order, price/cost origins, status thresholds — but the rows now
// arrive the only way production gets them: through the repository, on `load()`.
// The local-mutation groups are gone with the code they covered; their
// replacements assert the SERVER request (`inventory_phase4_writes_test.dart`).

import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

void main() {
  // Needed only by the location-hint group, which legitimately exercises
  // `shared_preferences` through its mock. Every other group builds a viewmodel
  // with no platform dependency at all.
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Variant 1 holds two lots of the same delivery series: 80 + 50 = 130.
  InventoryViewmodel seeded() {
    final products = FakeProductsRepository(
      products: [
        product(
          id: 1,
          name: 'Portland Cement',
          categoryName: 'Cement',
          brandName: 'Holcim',
          variants: [
            variant(
              id: 1,
              productId: 1,
              name: '40 kg Bag',
              threshold: 30,
              sellingUoms: [
                variantUom(
                  id: 1,
                  variantId: 1,
                  price: 270,
                  barcode: 'MAT-00001',
                  uomCode: 'BAG',
                ),
              ],
            ),
          ],
        ),
      ],
      batches: [
        batch(id: 1, variantId: 1, qty: 80, cost: 200, receiptId: 1),
        batch(id: 2, variantId: 1, qty: 50, cost: 235, receiptId: 2),
      ],
    );
    return InventoryViewmodel(
      products: products,
      inventory: FakeInventoryRepository(),
      catalogue: FakeCatalogueRepository(
        categories: [category(id: 1, name: 'Cement')],
      ),
    );
  }

  group('InventoryViewmodel — nothing is invented before the first load', () {
    test('a fresh store is EMPTY and has not loaded anything', () {
      final vm = InventoryViewmodel(
        products: FakeProductsRepository(),
        inventory: FakeInventoryRepository(),
        catalogue: FakeCatalogueRepository(),
      );

      // The mock seed is gone: twelve invented products used to be visible for a
      // frame, which is why the pages now show a spinner instead (hasLoaded).
      expect(vm.products, isEmpty);
      expect(vm.batches, isEmpty);
      expect(vm.categories, isEmpty);
      expect(vm.hasLoaded, isFalse);
    });

    test(
      'load() fills products, batches, categories, brands and units',
      () async {
        final vm = InventoryViewmodel(
          products: FakeProductsRepository(
            products: [product(id: 6)],
            batches: [batch(id: 6, variantId: 6)],
          ),
          inventory: FakeInventoryRepository(),
          catalogue: FakeCatalogueRepository(
            categories: [category(id: 1, name: 'Electrical')],
            brands: const [Brand(id: 1, name: 'Omni')],
            units: const [UnitOfMeasure(id: 1, code: 'PC', name: 'Piece')],
          ),
        );

        await vm.load();

        expect(vm.products.single.id, 6);
        expect(vm.batches.single.variantId, 6);
        expect(vm.categories.single.name, 'Electrical');
        expect(vm.brands.single.name, 'Omni');
        expect(vm.units.single.code, 'PC');
        expect(vm.hasLoaded, isTrue);
        expect(vm.isLoading, isFalse);
        expect(vm.loadError, isNull);
      },
    );

    test(
      'a failed load reports the message and keeps the rows already shown',
      () async {
        final products = FakeProductsRepository(
          products: [product(id: 6)],
          batches: [batch(id: 6, variantId: 6)],
        );
        final vm = InventoryViewmodel(
          products: products,
          inventory: FakeInventoryRepository(),
          catalogue: FakeCatalogueRepository(),
        );
        await vm.load();

        final failing = _FailingProductsRepository();
        final reloaded = InventoryViewmodel(
          products: failing,
          inventory: FakeInventoryRepository(),
          catalogue: FakeCatalogueRepository(),
        );
        await reloaded.load();

        // An empty list would render as a legitimate "no products"; the error is
        // the honest state, and `hasLoaded` stops the spinner.
        expect(reloaded.loadError, isNotNull);
        expect(reloaded.hasLoaded, isTrue);
      },
    );
  });

  group('InventoryViewmodel — stock lives on batches', () {
    test('stockOnHandFor sums every batch of a variant', () async {
      final vm = seeded();
      await vm.load();

      expect(vm.stockOnHandFor(1), 130.0);
    });

    test('batches are exposed oldest receipt first', () async {
      final vm = seeded();
      await vm.load();

      expect(vm.batchesFor(1).map((batch) => batch.receiptId).toList(), [1, 2]);
    });

    test(
      'the catalogue carries batch stock and the selling-uom price',
      () async {
        final vm = seeded();
        await vm.load();

        final row = vm.catalogue.firstWhere((item) => item.variant.id == 1);

        expect(row.price, 270.0); // VariantUom.defaultSellingPrice
        expect(row.stockOnHand, 130.0); // summed batches
        expect(row.uom.barcodeQr, 'MAT-00001');
      },
    );
  });

  // The three lookups the readers need. Each has exactly one home: barcode on the
  // selling unit, price on the selling unit (decision 08), cost on the newest
  // batch.
  group('InventoryViewmodel — field lookups', () {
    test('barcodeFor reads the selling uom, not a SKU', () async {
      final vm = seeded();
      await vm.load();

      expect(vm.barcodeFor(1), 'MAT-00001');
    });

    test('barcodeFor is empty when the variant is unknown', () async {
      final vm = seeded();
      await vm.load();

      expect(vm.barcodeFor(999999), '');
    });

    test(
      'priceFor reads the selling uom default, never a batch price',
      () async {
        final vm = seeded();
        await vm.load();

        expect(vm.priceFor(1), 270.0);
        expect(vm.priceFor(999999), isNull);
      },
    );

    test('costFor reads the NEWEST batch, labelled as such', () async {
      final vm = seeded();
      await vm.load();

      expect(vm.costFor(1), 235.0);
      expect(vm.costFor(999999), isNull);
    });

    test('variantFor finds a variant across products', () async {
      final vm = seeded();
      await vm.load();

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
      final vm = seeded();

      expect(vm.locationHints, isEmpty);
      expect(vm.locationHintFor(1), '');
    });

    test('a saved hint is readable and survives a new viewmodel', () async {
      final vm = seeded();

      await vm.setLocationHint(1, 'Rack A-01');
      expect(vm.locationHintFor(1), 'Rack A-01');

      final reopened = seeded();
      await reopened.loadLocationHints();
      expect(reopened.locationHintFor(1), 'Rack A-01');
    });

    test('hints are keyed by variant, not product', () async {
      final vm = seeded();

      await vm.setLocationHint(1, 'Rack A-01');
      await vm.setLocationHint(2, 'Yard E-02');

      expect(vm.locationHintFor(1), 'Rack A-01');
      expect(vm.locationHintFor(2), 'Yard E-02');
    });

    test('an empty hint reads back as no hint', () async {
      final vm = seeded();
      await vm.setLocationHint(1, 'Rack A-01');

      await vm.setLocationHint(1, '   ');

      expect(vm.locationHintFor(1), '');
      expect(vm.locationHints, isEmpty);
    });

    test('setting a hint notifies listeners', () async {
      final vm = seeded();
      var notified = 0;
      vm.addListener(() => notified++);

      await vm.setLocationHint(1, 'Rack A-01');

      expect(notified, greaterThan(0));
    });
  });

  // Status must be derived from the batch total with the SERVER's predicate
  // (decision 13, rule 2): `total <= 0` is out of stock, `threshold > 0 &&
  // total < threshold` is low, anything else is in stock.
  group('InventoryViewmodel — status from batch stock', () {
    InventoryViewmodel withStock(double qty, {double threshold = 30}) {
      return InventoryViewmodel(
        products: FakeProductsRepository(
          products: [
            product(
              id: 1,
              variants: [variant(id: 1, productId: 1, threshold: threshold)],
            ),
          ],
          batches: [batch(id: 1, variantId: 1, qty: qty)],
        ),
        inventory: FakeInventoryRepository(),
        catalogue: FakeCatalogueRepository(),
      );
    }

    test('a variant above its threshold is in stock', () async {
      final vm = withStock(130);
      await vm.load();

      expect(vm.statusForVariant(1), InventoryStockStatus.inStock);
    });

    test('a variant below its threshold is low stock', () async {
      final vm = withStock(25);
      await vm.load();

      expect(vm.statusForVariant(1), InventoryStockStatus.lowStock);
    });

    test(
      'a variant ON its threshold is in stock, as the server says',
      () async {
        final vm = withStock(30);
        await vm.load();

        expect(vm.statusForVariant(1), InventoryStockStatus.inStock);
      },
    );

    test('an empty variant is out of stock', () async {
      final vm = withStock(0);
      await vm.load();

      expect(vm.statusForVariant(1), InventoryStockStatus.outOfStock);
    });

    test('a zero threshold never reads as low stock', () async {
      final vm = withStock(1, threshold: 0);
      await vm.load();

      expect(vm.statusForVariant(1), InventoryStockStatus.inStock);
    });

    test('an unknown variant is out of stock, not a crash', () {
      final vm = withStock(1);

      expect(vm.statusForVariant(999999), InventoryStockStatus.outOfStock);
    });
  });
}

/// A repository whose catalogue read always fails, for the error-path test.
class _FailingProductsRepository extends FakeProductsRepository {
  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    throw const ProductsServiceException(
      'Cannot connect to the BuildPro server.',
    );
  }
}
