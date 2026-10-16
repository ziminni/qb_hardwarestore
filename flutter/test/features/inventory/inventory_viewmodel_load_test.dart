// Phase 1 (decision 12): the product list has exactly ONE home —
// `InventoryViewmodel` — and Phase 1 makes that home API-backed.
//
// The load contract these tests pin:
//   * a successful load REPLACES the mock catalogue with the API's
//   * a FAILED load surfaces its message and does NOT quietly empty or half-fill
//     the catalogue (decision 12 rule 3: failures surface, they do not silently
//     empty, and a stale list must never present itself as current)
//   * the mock is retained for what the API cannot serve yet, so a load must not
//     disturb movements, adjustments or tracking

import 'dart:async';

import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

/// The API's catalogue as the live one looked on 2026-10-16: ONE product with
/// ONE variant, against a mock catalogue of ten. The sizes differ on purpose —
/// that is how these tests can tell which source won.
ProductsSnapshot _apiSnapshot() => ProductsSnapshot(
  products: [
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
          id: 8,
          variantName: '20A 1-pole',
          baseUomCode: 'PC',
          isActive: true,
          minStockThreshold: 5,
          sellingUoms: [
            VariantUom(
              id: 8,
              variantId: 8,
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
    ),
  ],
  batches: [
    InventoryBatch(
      id: 6,
      variantId: 8,
      receiptId: 6,
      initialQty: 100,
      currentQty: 100,
      unitCostLanded: 180,
      markupPercentage: 0,
      batchSellingPrice: 180,
      expirationDate: null,
      createdAt: null,
    ),
  ],
);

class _FakeProductsRepository extends ProductsRepository {
  _FakeProductsRepository({this.snapshot})
    : error = null,
      super(ProductsService());

  ProductsSnapshot? snapshot;
  ProductsServiceException? error;
  int calls = 0;

  /// Completes only when the test releases it, so "in flight" is observable.
  Future<void>? gate;

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    calls++;
    if (gate != null) await gate;
    final failure = error;
    if (failure != null) throw failure;
    return snapshot!;
  }
}

void main() {
  late _FakeProductsRepository products;

  setUp(() => products = _FakeProductsRepository(snapshot: _apiSnapshot()));

  test('the store starts on the mock catalogue, not the API one', () {
    // Establishes the baseline the next test moves away from. Asserted by
    // identity rather than by a hard-coded count, so this does not break every
    // time the mock gains a product: 'Circuit Breaker' is the API's product in
    // the snapshot above, so its ABSENCE is what proves the mock is in play.
    final store = InventoryViewmodel(products: products);

    expect(store.products, isNotEmpty);
    expect(
      store.products.map((product) => product.baseName),
      isNot(contains('Circuit Breaker')),
    );
    expect(store.isLoading, isFalse);
    expect(store.loadError, isNull);
  });

  test('load() replaces the mock catalogue with the API data', () async {
    final store = InventoryViewmodel(products: products);

    await store.load();

    expect(store.products, hasLength(1));
    expect(store.products.single.baseName, 'Circuit Breaker');
    // Stock moves with it, or the assembler would pair live products with mock
    // batches and invent quantities.
    expect(store.stockOnHandFor(8), 100);
    expect(products.calls, 1);
  });

  test('it reports loading while the fetch is in flight', () async {
    final store = InventoryViewmodel(products: products);
    final gate = Completer<void>();
    products.gate = gate.future;
    var notifications = 0;
    store.addListener(() => notifications++);

    final pending = store.load();

    expect(
      store.isLoading,
      isTrue,
      reason: 'AsyncView must be able to show it',
    );
    expect(notifications, greaterThan(0));

    gate.complete();
    await pending;

    expect(store.isLoading, isFalse);
    expect(store.loadError, isNull);
  });

  test('a failed load surfaces the message and keeps the catalogue', () async {
    final store = InventoryViewmodel(products: products);
    final before = store.products.map((product) => product.baseName).toList();
    products.error = const ProductsServiceException('Cannot connect.');

    await store.load();

    expect(store.loadError, 'Cannot connect.');
    expect(store.isLoading, isFalse);
    // The assertion that matters: a failed load must leave the catalogue EXACTLY
    // as it was. Emptying it would render as a legitimate "no products" the user
    // cannot act on, and half-filling it would invent a catalogue. Compared
    // against the captured baseline rather than a count, because the property is
    // "unchanged", not "a particular size".
    expect(store.products.map((product) => product.baseName).toList(), before);
  });

  test('a failed load can be retried and then succeeds', () async {
    final store = InventoryViewmodel(products: products);
    products.error = const ProductsServiceException('Cannot connect.');
    await store.load();

    products.error = null;
    await store.load();

    expect(store.loadError, isNull, reason: 'a retry must clear the old error');
    expect(store.products, hasLength(1));
    expect(products.calls, 2);
  });

  test('a load leaves the data the API cannot serve yet alone', () async {
    // Decision 12 keeps the mock as the fallback for movements, adjustments and
    // tracking until their phases land. A catalogue load must not wipe them.
    final store = InventoryViewmodel(products: products);
    final movementsBefore = store.movements.length;
    expect(movementsBefore, greaterThan(0), reason: 'the mock seeds these');

    await store.load();

    expect(store.movements, hasLength(movementsBefore));
  });

  test('hasLoaded is false until an attempt has finished', () async {
    // The screen needs to tell "not fetched yet" from "fetched and empty".
    // Without it the page renders the 12 mock products for one frame before the
    // API's 6 arrive — a visible flash of data that is not real.
    final store = InventoryViewmodel(products: products);

    expect(store.hasLoaded, isFalse);

    await store.load();

    expect(store.hasLoaded, isTrue);
  });

  test('a FAILED attempt still counts as loaded, so the error shows', () async {
    // If a failure left hasLoaded false the page would sit on a spinner forever
    // instead of offering the retry it can actually perform.
    final store = InventoryViewmodel(products: products);
    products.error = const ProductsServiceException('Cannot connect.');

    await store.load();

    expect(store.hasLoaded, isTrue);
    expect(store.loadError, 'Cannot connect.');
  });
}
