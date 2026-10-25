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

import 'package:client/data/models/product_writes.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/viewmodels/products_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeProductsRepository products;
  late InventoryViewmodel inventory;
  late ProductsViewmodel vm;

  setUp(() async {
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
}
