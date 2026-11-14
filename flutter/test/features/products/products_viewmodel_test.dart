// Decision 11: `ProductsViewmodel` is **view state only**. It owns search,
// filters, paging and selection, and NO product data.
//
// Before this, it held a COPY of the product list taken at construction
// (`ProductsViewmodel(context.read<InventoryViewmodel>().products)`), and
// `products_page` applied every mutation to BOTH viewmodels — each computing its
// own `max(id)+1`, so the two could disagree. The duplication is what these tests
// exist to prevent from coming back.
//
// Phase 4 Task 4 rewrote the mutation group: the store no longer mutates in
// memory, so "delegates to the store" now means "sends the draft to the
// repository". The store is seeded from a fake catalogue instead of
// `InventoryMockData`, which was deleted with the seed.

import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_writes.dart';
import 'package:client/data/models/stock_on_hand.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/viewmodels/products_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeProductsRepository products;
  late InventoryViewmodel inventory;
  late ProductsViewmodel vm;

  setUp(() async {
    // Creating or editing a product also records the storage location on THIS
    // device (decision 15), which goes through shared_preferences.
    SharedPreferences.setMockInitialValues({});
    products = FakeProductsRepository(
      products: [
        product(
          id: 1,
          name: 'Portland Cement',
          categoryName: 'Cement',
          brandName: 'Holcim',
        ),
        product(
          id: 2,
          name: 'PVC Pipe',
          categoryName: 'Plumbing',
          brandName: 'Neltex',
        ),
        product(
          id: 3,
          name: 'Old Hammer',
          categoryName: 'Hand Tools',
          brandName: 'Stanley',
          isActive: false,
        ),
      ],
      batches: [batch(id: 1, variantId: 1, qty: 40)],
    );
    inventory = InventoryViewmodel(
      products: products,
      inventory: FakeInventoryRepository(),
      catalogue: FakeCatalogueRepository(),
    );
    await inventory.load();
    vm = ProductsViewmodel(inventory);
  });

  tearDown(() => vm.dispose());

  group('ProductsViewmodel reads the store live (decision 11)', () {
    test("its product list IS the store's, not a copy", () async {
      expect(vm.products.length, 3);

      // The proof it is not a snapshot: change the STORE (as a reload would) and
      // read the viewmodel.
      products.setSnapshot(products: [product(id: 9, name: 'Only One')]);
      await inventory.load();

      expect(vm.products.single.id, 9);
      expect(vm.products.length, inventory.products.length);
    });

    test("a store change notifies the viewmodel's listeners", () async {
      var notified = 0;
      vm.addListener(() => notified++);

      products.setSnapshot(products: [product(id: 4, name: 'Fresh Product')]);
      await inventory.load();

      expect(
        notified,
        greaterThan(0),
        reason: 'the screen would not rebuild without this',
      );
    });

    test('it stops listening once disposed', () async {
      // If the listener leaked, a later store change would call notifyListeners
      // on a dead ChangeNotifier and Flutter would throw.
      //
      // Uses a LOCAL instance on purpose: disposing the shared `vm` here would
      // make tearDown dispose it a second time, which Flutter also throws for.
      ProductsViewmodel(inventory).dispose();

      products.setSnapshot(products: [product(id: 5)]);
      await expectLater(inventory.load(), completes);
    });
  });

  group('ProductsViewmodel filters (unchanged behaviour)', () {
    test('only active products are listed', () {
      // `products` is the store's whole list (archived rows included — the
      // archived dialog reads them); the TABLE shows only active ones.
      expect(vm.products, hasLength(3));
      expect(vm.archivedProducts, 1);
      expect(vm.filteredProducts.every((product) => product.isActive), isTrue);
      expect(vm.filteredProducts, hasLength(2));
    });

    test('search matches a product name', () {
      vm.setSearchQuery('Portland');

      expect(vm.filteredProducts, isNotEmpty);
      expect(
        vm.filteredProducts.every(
          (product) => product.baseName.toLowerCase().contains('portland'),
        ),
        isTrue,
      );
    });

    test('search matches a variant name and barcode', () {
      vm.setSearchQuery('20A');

      expect(vm.filteredProducts, isNotEmpty);

      vm.setSearchQuery('NOT-A-BARCODE');
      expect(vm.filteredProducts, isEmpty);
    });

    test('category and brand filters narrow the list', () {
      vm.setCategory('Cement');
      expect(vm.filteredProducts.single.id, 1);

      vm.clearFilters();
      vm.setBrand('Neltex');
      expect(vm.filteredProducts.single.id, 2);
    });
  });

  group('ProductsViewmodel writes go to the server (Phase 4 Task 4)', () {
    test('createProduct hands the draft to the repository', () async {
      const draft = NewProductDraft(
        categoryId: 1,
        brandId: 1,
        baseName: 'Delegated Product',
        description: '',
        imageUrl: '',
        variantName: 'Standard',
        baseUomId: 1,
        minStockThreshold: 5,
        maxStockLevel: 100,
        sellingPrice: 250,
      );

      final error = await vm.createProduct(draft);

      expect(error, isNull);
      expect(products.createdDrafts.single.baseName, 'Delegated Product');
      expect(products.createdDrafts.single.sellingPrice, 250);
    });

    test('a refused create returns the message and reloads', () async {
      products.failAt = ProductWriteStep.variant;

      final error = await vm.createProduct(
        const NewProductDraft(
          categoryId: 1,
          brandId: 1,
          baseName: 'Half Made',
          description: '',
          imageUrl: '',
          variantName: 'Standard',
          baseUomId: 1,
          minStockThreshold: 0,
          maxStockLevel: 0,
          sellingPrice: 1,
        ),
      );

      expect(error, 'The variant could not be created: server said no');
      expect(products.loadCount, greaterThan(1));
    });

    test('editProduct hands the PATCH draft to the repository', () async {
      final error = await vm.editProduct(
        const ProductEditDraft(
          productId: 1,
          variantId: 1,
          sellingUnitId: 1,
          sellingPrice: 275,
        ),
      );

      expect(error, isNull);
      expect(products.editDrafts.single.sellingPrice, 275);
      expect(products.editDrafts.single.sellingUnitBody, {
        'default_selling_price': 275.0,
      });
    });

    test('setProductActive PATCHes is_active, it does not delete', () async {
      final target = vm.products.first;

      final error = await vm.setProductActive(target, false);

      expect(error, isNull);
      expect(products.activePatches.single, (productId: 1, isActive: false));
    });

    test(
      'archiveSelectedProducts PATCHes each selected product once',
      () async {
        vm.selectVisibleProducts(true);
        final selected = vm.selectedProductIds.length;
        expect(selected, greaterThan(0));

        await vm.archiveSelectedProducts();

        expect(products.activePatches, hasLength(selected));
        expect(
          products.activePatches.every((patch) => patch.isActive == false),
          isTrue,
        );
        expect(vm.selectedProductIds, isEmpty);
      },
    );
  });

  // Task 19 (POS usability): narrow the catalogue to shelves that really hold
  // stock. The rule is the `/stock-on-hand/` rows, NEVER the product's
  // `stored_at` home: a product homed at Store whose units sit in the Bodega is
  // a Bodega match, and the home shelf must not put it under Store.
  group('Stock location filter (physical stock, Task 19)', () {
    late InventoryViewmodel store;
    late FakeProductsRepository storeRepo;
    late ProductsViewmodel locationVm;

    List<Product> locationProducts() => [
      // Home shelf Store, every unit in the Bodega.
      product(
        id: 1,
        name: 'Portland Cement',
        categoryName: 'Cement',
        brandName: 'Holcim',
        storedAtId: 1,
      ),
      // Home shelf Bodega, every unit in the Store.
      product(
        id: 2,
        name: 'PVC Pipe',
        categoryName: 'Plumbing',
        brandName: 'Neltex',
        storedAtId: 2,
      ),
      // No stock-on-hand row at all.
      product(
        id: 3,
        name: 'Old Hammer',
        categoryName: 'Hand Tools',
        brandName: 'Stanley',
      ),
      // Two variants: one row at zero, one holding seven in the Bodega.
      product(
        id: 4,
        name: 'Cable Bundle',
        categoryName: 'Electrical',
        brandName: 'Omni',
        variants: [
          variant(id: 44, productId: 4),
          variant(id: 45, productId: 4, name: '50 m roll'),
        ],
      ),
      // Stock sits on a DEACTIVATED shelf the location list does not send.
      product(
        id: 5,
        name: 'Shop Rags',
        categoryName: 'Cement',
        brandName: 'ABC',
      ),
    ];

    List<StockOnHand> locationStock() => [
      onHand(
        variantId: 1,
        locationId: 2,
        locationName: 'Bodega',
        isHome: false,
        qty: 40,
      ),
      onHand(variantId: 2, locationId: 1, locationName: 'Store', qty: 25),
      onHand(variantId: 44, locationId: 1, locationName: 'Store', qty: 0),
      onHand(
        variantId: 45,
        locationId: 2,
        locationName: 'Bodega',
        isHome: false,
        qty: 7,
      ),
      onHand(
        variantId: 5,
        locationId: 3,
        locationName: 'Old Shed',
        isHome: false,
        locationActive: false,
        qty: 5,
      ),
    ];

    /// The metadata list the server sends: the deactivated "Old Shed" is not in
    /// it, which is exactly the shelf the filter must still offer.
    List<StorageLocation> locationCatalogue() => const [
      StorageLocation(id: 1, name: 'Store'),
      StorageLocation(id: 2, name: 'Bodega'),
    ];

    Future<void> seed({
      List<StockOnHand>? stockOnHand,
      List<StorageLocation>? locations,
      List<InventoryBatch> batches = const [],
    }) async {
      storeRepo = FakeProductsRepository(
        products: locationProducts(),
        batches: batches,
        stockOnHand: stockOnHand ?? locationStock(),
      );
      store = InventoryViewmodel(
        products: storeRepo,
        inventory: FakeInventoryRepository(),
        catalogue: FakeCatalogueRepository(),
        storageLocations: FakeStorageLocationRepository(
          locations: locations ?? locationCatalogue(),
        ),
      );
      await store.load();
      locationVm = ProductsViewmodel(store);
      addTearDown(() {
        locationVm.dispose();
        store.dispose();
      });
    }

    List<int> ids() => locationVm.filteredProducts.map((p) => p.id).toList();

    test('with no location chosen every active product stays listed', () async {
      await seed();

      expect(locationVm.selectedStockLocationId, isNull);
      expect(ids(), [
        1,
        2,
        3,
        4,
        5,
      ], reason: '"All locations" must keep the no-stock rows visible');
    });

    test('the choices are the server ids and names, including a shelf only the '
        'on-hand rows name', () async {
      await seed();

      expect(locationVm.stockLocationOptions.map((o) => (o.id, o.name)), [
        (2, 'Bodega'),
        (3, 'Old Shed'),
        (1, 'Store'),
      ]);
    });

    test(
      'a product homed at Store but stocked in the Bodega matches Bodega, not '
      'Store',
      () async {
        await seed();

        locationVm.setStockLocation(1);
        expect(ids(), [2]);

        locationVm.setStockLocation(2);
        expect(ids(), [1, 4]);
      },
    );

    test(
      'ANY variant holding stock at the location matches the product',
      () async {
        await seed();

        locationVm.setStockLocation(2);

        expect(
          ids(),
          contains(4),
          reason: 'variant 45 holds 7 in the Bodega while variant 44 is empty',
        );
      },
    );

    test('a zero-quantity row is not stock there', () async {
      await seed();

      locationVm.setStockLocation(1);

      expect(ids(), isNot(contains(4)));
    });

    test('a product with no on-hand row is visible only under All '
        'locations', () async {
      await seed();

      expect(ids(), contains(3));

      locationVm.setStockLocation(1);
      expect(ids(), isNot(contains(3)));
    });

    test('a deactivated shelf keeps its real stock selectable', () async {
      await seed();

      locationVm.setStockLocation(3);

      expect(ids(), [5]);
    });

    test('batches are never the quantity source', () async {
      await seed(
        // The old derivation would call this 500 on hand. The server's on-hand
        // rows say the Store holds none, and they are the authority.
        batches: [batch(id: 90, variantId: 2, qty: 500)],
        stockOnHand: [
          onHand(variantId: 2, locationId: 1, locationName: 'Store', qty: 0),
        ],
      );

      locationVm.setStockLocation(1);

      expect(locationVm.filteredProducts, isEmpty);
    });

    test('it combines with search, category and brand', () async {
      await seed();

      locationVm.setStockLocation(2);
      locationVm.setCategory('Cement');
      expect(ids(), [
        1,
      ], reason: 'Shop Rags is Cement but its stock is elsewhere');

      locationVm.setCategory(null);
      locationVm.setStockLocation(1);
      locationVm.setBrand('Neltex');
      expect(ids(), [2]);

      locationVm.clearFilters();
      locationVm.setSearchQuery('hammer');
      locationVm.setStockLocation(2);
      expect(ids(), isEmpty);

      locationVm.clearFilters();
      locationVm.setSearchQuery('cable');
      locationVm.setStockLocation(2);
      expect(ids(), [4]);
    });

    test('clearFilters returns to All locations', () async {
      await seed();
      locationVm.setStockLocation(2);

      locationVm.clearFilters();

      expect(locationVm.selectedStockLocationId, isNull);
      expect(ids(), hasLength(5));
    });

    test('choosing a location resets paging and the selection', () async {
      await seed();
      locationVm.setRowsPerPage(1);
      locationVm.goToPage(3);
      locationVm.toggleSelection(1, true);

      locationVm.setStockLocation(2);

      expect(locationVm.currentPage, 1);
      expect(locationVm.selectedProductIds, isEmpty);
      expect(locationVm.visibleProducts.map((p) => p.id), [1]);
    });

    test('a reload re-reads the filter from the new on-hand rows', () async {
      await seed();
      locationVm.setStockLocation(1);
      expect(ids(), [2]);

      storeRepo.setSnapshot(
        products: locationProducts(),
        stockOnHand: [
          onHand(variantId: 1, locationId: 1, locationName: 'Store', qty: 12),
        ],
      );
      await store.load();

      expect(ids(), [
        1,
      ], reason: 'the filter must read the store live, not a snapshot');
    });
  });
}
