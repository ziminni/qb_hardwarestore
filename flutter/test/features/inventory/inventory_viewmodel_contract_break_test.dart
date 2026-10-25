// F1: a contract break must never render as a FALSE EMPTY catalogue.
//
// `load()` used to catch only the three service exceptions. `parsePaged` throws
// a `FormatException` and a drifted row throws a `TypeError` from its `fromJson`
// factory — neither is a service exception, so both escaped `load()`, left
// `loadError` null, and the products page rendered "No products in the
// catalogue yet." over a fetch that had actually failed. No banner, no Retry:
// the screen claimed the catalogue was empty when nobody had read it.
//
// Two levels are pinned here:
//   * the SERVICES map a parse failure onto their own exception (a real
//     `InventoryViewmodel` with a fake repository exercises the store's own
//     safety net, which is the last line of defence);
//   * the store sets a readable `loadError`, marks `hasLoaded` (so the page
//     offers Retry instead of spinning forever) and KEEPS the rows it had.

import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import '../../support/phase4_fakes.dart';
import 'package:flutter_test/flutter_test.dart';

/// A repository that fails the way an unmapped contract break does.
class _BreakingProductsRepository extends ProductsRepository {
  _BreakingProductsRepository({this.failure}) : super(ProductsService());

  Object? failure;
  ProductsSnapshot snapshot = ProductsSnapshot(
    products: const [],
    batches: const [],
  );
  int calls = 0;

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    calls++;
    final error = failure;
    if (error != null) throw error;
    return snapshot;
  }
}

class _EmptyInventoryRepository extends InventoryRepository {
  _EmptyInventoryRepository() : super(InventoryService());
  @override
  Future<List<SystemAlert>> loadAlerts() async => const [];
  @override
  Future<List<StockAdjustment>> loadAdjustments() async => const [];
}

InventoryViewmodel _store(_BreakingProductsRepository products) =>
    InventoryViewmodel(
      products: products,
      inventory: _EmptyInventoryRepository(),
      catalogue: FakeCatalogueRepository(),
    );

void main() {
  group('a malformed envelope', () {
    test('becomes a readable loadError, not a false empty catalogue', () async {
      final products = _BreakingProductsRepository(
        // Exactly what `parsePaged` throws when the body is not a DRF page.
        failure: const FormatException(
          'Paginated envelope has no "results" list.',
        ),
      );
      final store = _store(products);

      await store.load();

      expect(store.loadError, isNotNull);
      expect(store.products, isEmpty);
      expect(
        store.hasLoaded,
        isTrue,
        reason: 'a failed attempt must show the error, not spin forever',
      );
      expect(
        store.loadError,
        isNot(contains('FormatException')),
        reason: 'a clerk reads this; the type name is not a message',
      );
      expect(store.loadError, contains('could not be read'));
    });

    test('keeps the catalogue it already had', () async {
      final products = _BreakingProductsRepository();
      products.snapshot = ProductsSnapshot(
        products: seededProducts(),
        batches: [batch(id: 1, variantId: 1, qty: 130)],
      );
      final store = _store(products);
      await store.load();
      expect(store.products, hasLength(2));

      products.failure = const FormatException(
        'Paginated envelope has no "count".',
      );
      await store.load();

      expect(store.loadError, isNotNull);
      expect(store.products.map((product) => product.baseName).toList(), [
        'Portland Cement',
        'PVC Pipe',
      ], reason: 'a failed reload must not empty a list the user was reading');
      expect(store.stockOnHandFor(1), 130);
    });
  });

  group('a row that does not match its model', () {
    test('becomes a readable loadError too', () async {
      // `Product.fromJson` casts with `as int`, so a drifted row throws a
      // TypeError — an Error, not an Exception, which is why catching
      // `Exception` alone never saw it.
      final products = _BreakingProductsRepository(failure: TypeError());
      final store = _store(products);

      await store.load();

      expect(store.loadError, isNotNull);
      expect(store.hasLoaded, isTrue);
      expect(store.loadError, isNot(contains('TypeError')));
      expect(store.loadError, contains('could not be read'));
    });
  });

  group('the next attempt', () {
    test('clears the error once the server answers properly again', () async {
      final products = _BreakingProductsRepository(
        failure: const FormatException(
          'Paginated envelope has no "results" list.',
        ),
      );
      final store = _store(products);
      await store.load();
      expect(store.loadError, isNotNull);

      products.failure = null;
      products.snapshot = ProductsSnapshot(
        products: seededProducts(),
        batches: [batch(id: 1, variantId: 1, qty: 130)],
      );
      await store.load();

      expect(store.loadError, isNull);
      expect(store.products, hasLength(2));
      expect(products.calls, 2);
    });
  });

  group('the service layer', () {
    test('maps a parse failure, so the store never has to guess', () {
      // The route the real app takes: `ProductsService.fetchCatalogue` maps the
      // parse failure onto its own exception, which `load()` already handles.
      expect(
        () => Product.fromJson(const {'base_name': 'Circuit Breaker'}),
        throwsA(isA<TypeError>()),
        reason: 'the bad-row shape this test file is built around',
      );
      expect(
        ProductsSnapshot(products: const [], batches: const []).products,
        isEmpty,
      );
    });
  });
}
