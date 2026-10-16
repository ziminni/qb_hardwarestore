// Decision 11: `ProductsViewmodel` is **view state only**. It owns search,
// filters, sort, paging and selection, and NO product data.
//
// Before this, it held a COPY of the product list taken at construction
// (`ProductsViewmodel(context.read<InventoryViewmodel>().products)`), and
// `products_page` applied every mutation to BOTH viewmodels — each computing its
// own `max(id)+1`, so the two could disagree. The duplication is what these tests
// exist to prevent from coming back.

import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/viewmodels/products_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

Product _draft({
  required int id,
  String baseName = 'Test Product',
  String categoryName = 'Cement',
  String brandName = 'Holcim',
  bool isActive = true,
  List<ProductVariant> variants = const [],
}) => Product(
  id: id,
  categoryId: 1,
  categoryName: categoryName,
  brandId: 1,
  brandName: brandName,
  baseName: baseName,
  description: '',
  imageUrl: '',
  isActive: isActive,
  variants: variants,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InventoryViewmodel inventory;
  late ProductsViewmodel vm;

  setUp(() {
    inventory = InventoryViewmodel();
    vm = ProductsViewmodel(inventory);
  });

  tearDown(() => vm.dispose());

  group('ProductsViewmodel reads the store live (decision 11)', () {
    test('its product list IS the store\'s, not a copy', () {
      expect(vm.products.length, inventory.products.length);

      // The proof it is not a snapshot: mutate the store, read the viewmodel.
      // (InventoryViewmodel has no `archiveProduct`; archiving is an update.)
      inventory.updateProduct(
        inventory.products.first.copyWith(isActive: false),
      );

      expect(
        vm.products.length,
        inventory.products.length,
        reason: 'viewmodel list drifted from the store',
      );
    });

    test('a store change notifies the viewmodel\'s listeners', () {
      var notified = 0;
      vm.addListener(() => notified++);

      inventory.addProduct(_draft(id: 0, baseName: 'Fresh Product'));

      expect(
        notified,
        greaterThan(0),
        reason: 'the screen would not rebuild without this',
      );
    });

    test('it stops listening once disposed', () {
      // If the listener leaked, a later store change would call
      // notifyListeners on a dead ChangeNotifier and Flutter would throw.
      //
      // Uses a LOCAL instance on purpose: disposing the shared `vm` here would
      // make tearDown dispose it a second time, which Flutter also throws for.
      ProductsViewmodel(inventory).dispose();

      expect(
        () => inventory.addProduct(_draft(id: 0, baseName: 'After Dispose')),
        returnsNormally,
      );
    });
  });

  group('ProductsViewmodel filters (unchanged behaviour)', () {
    test('only active products are listed', () {
      expect(vm.products.every((product) => product.isActive), isTrue);
      expect(vm.filteredProducts.every((product) => product.isActive), isTrue);
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

    test('search matches a variant barcode, not just the product', () {
      // The migrated behaviour: search used to look at sku + qrIdentifier, which
      // no longer exist. A barcode lives on the selling unit.
      final barcode = inventory
          .products
          .expand((product) => product.variants)
          .map((variant) => variant.barcode)
          .firstWhere((value) => value.isNotEmpty);

      vm.setSearchQuery(barcode);

      expect(vm.filteredProducts, isNotEmpty);
    });

    test('a search that matches nothing returns nothing', () {
      vm.setSearchQuery('zzz-nothing-matches');

      expect(vm.filteredProducts, isEmpty);
      expect(vm.visibleProducts, isEmpty);
      expect(vm.firstVisibleItem, 0);
    });

    test('the category filter narrows to that category', () {
      vm.setCategory('Plumbing');

      expect(vm.filteredProducts, isNotEmpty);
      expect(
        vm.filteredProducts.every(
          (product) => product.categoryName == 'Plumbing',
        ),
        isTrue,
      );
    });

    test('the brand filter narrows to that brand', () {
      final brand = inventory.products.first.brandName;
      vm.setBrand(brand);

      expect(
        vm.filteredProducts.every((product) => product.brandName == brand),
        isTrue,
      );
    });

    test('clearFilters restores the full list', () {
      vm.setSearchQuery('zzz-nothing-matches');
      expect(vm.filteredProducts, isEmpty);

      vm.clearFilters();

      expect(vm.filteredProducts.length, vm.products.length);
      expect(vm.selectedCategory, isNull);
      expect(vm.selectedBrand, isNull);
    });
  });

  group('ProductsViewmodel paging and selection (unchanged behaviour)', () {
    test('a page holds at most rowsPerPage products', () {
      vm.setRowsPerPage(3);

      expect(vm.visibleProducts.length, lessThanOrEqualTo(3));
      expect(vm.firstVisibleItem, 1);
    });

    test('totalPages covers the filtered list', () {
      vm.setRowsPerPage(3);
      final expected = (vm.filteredProducts.length / 3).ceil();

      expect(vm.totalPages, expected < 1 ? 1 : expected);
    });

    test('paging past the end is clamped', () {
      vm.goToPage(9999);

      expect(vm.currentPage, vm.totalPages);
    });

    test('selection survives paging but not a filter change', () {
      final first = vm.visibleProducts.first;
      vm.toggleSelection(first.id, true);
      vm.goToPage(2);
      expect(vm.selectedProductIds, contains(first.id));

      vm.setSearchQuery('a');
      expect(
        vm.selectedProductIds,
        isEmpty,
        reason: 'a selection made under other filters is meaningless',
      );
    });
  });

  group('ProductsViewmodel mutations delegate to the store (decision 11)', () {
    test('addProduct writes to the store, not to a private list', () {
      final before = inventory.products.length;

      vm.addProduct(_draft(id: 0, baseName: 'Delegated Product'));

      expect(inventory.products.length, before + 1);
      expect(
        inventory.products.any((p) => p.baseName == 'Delegated Product'),
        isTrue,
      );
      expect(vm.products.length, inventory.products.length);
    });

    test('addProduct gives the product a real id from the store', () {
      vm.addProduct(_draft(id: 0, baseName: 'Needs An Id'));

      final stored = inventory.products.firstWhere(
        (p) => p.baseName == 'Needs An Id',
      );
      expect(stored.id, greaterThan(0));
    });

    test('addProduct passes the opening stock through as batches', () {
      final variant = const ProductVariant(
        id: 9901,
        productId: 0,
        baseUomId: 1,
        minStockThreshold: 5,
        maxStockLevel: 0,
        variantName: 'Delegated Variant',
        baseUomCode: 'Bag',
        isActive: true,
      );

      vm.addProduct(
        _draft(id: 0, baseName: 'With Stock', variants: [variant]),
        openingStock: const [
          InventoryBatch(
            id: 0,
            variantId: 9901,
            receiptId: 0,
            initialQty: 25,
            currentQty: 25,
            unitCostLanded: 100,
            markupPercentage: 0,
            batchSellingPrice: 120,
            expirationDate: null,
            createdAt: null,
          ),
        ],
      );

      expect(inventory.stockOnHandFor(9901), 25.0);
    });

    test('updateProduct writes through to the store', () {
      final target = inventory.products.first;

      vm.updateProduct(target.copyWith(baseName: 'Renamed Product'));

      expect(
        inventory.products.any((p) => p.baseName == 'Renamed Product'),
        isTrue,
      );
      expect(
        vm.products.any((p) => p.baseName == 'Renamed Product'),
        isTrue,
      );
    });

    test('archiveProduct deactivates it in the store', () {
      final target = inventory.products.first;

      vm.archiveProduct(target);

      expect(
        inventory.products.firstWhere((p) => p.id == target.id).isActive,
        isFalse,
      );
    });

    test('archiveSelectedProducts deactivates each selected product once', () {
      final selected = vm.visibleProducts.take(2).toList();
      for (final product in selected) {
        vm.toggleSelection(product.id, true);
      }

      vm.archiveSelectedProducts();

      for (final product in selected) {
        expect(
          inventory.products.firstWhere((p) => p.id == product.id).isActive,
          isFalse,
          reason: 'product ${product.id} was not archived',
        );
      }
      expect(vm.selectedProductIds, isEmpty);
      // The store owns the ids, so exactly one product was added per archive.
      expect(
        inventory.products.map((p) => p.id).toSet().length,
        inventory.products.length,
        reason: 'archiving duplicated a product id',
      );
    });
  });
}
