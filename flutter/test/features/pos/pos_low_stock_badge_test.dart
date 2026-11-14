// Phase 6 F1 item 18 (decision 22): the till's stock badge follows the SERVER's
// low-stock rule instead of a hardcoded 10.
//
// Backend truth (`apps/inventory/services.py::_check_low_stock`, LOW_STOCK
// branch): `0 < base stock < variant.min_stock_threshold` — strictly below, and
// only when the threshold is above zero. Two traps:
//   * `CatalogueItem.isLowStock` says `<=`, so it disagrees exactly AT the
//     threshold. The badge must not use it.
//   * the verdict is on BASE stock while the badge PRINTS the sale quantity, so
//     a conversion factor must not change the answer (a box row reads "10.4 box
//     left" and is still low because 260 base < 300 threshold).

import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_product_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

/// A one-row till whose variant carries [threshold] and whose shelf holds
/// [stock] BASE units. [factor] is the selling unit's conversion factor, so a
/// factor above 1 makes the sale quantity differ from the base stock.
PosTransactionViewmodel _till({
  required double threshold,
  required double stock,
  double factor = 1,
  String unit = 'PC',
}) {
  final products = [
    product(
      id: 1,
      name: 'Portland Cement',
      categoryName: 'Cement',
      variants: [
        variant(
          id: 1,
          productId: 1,
          name: '40kg',
          threshold: threshold,
          baseUomCode: unit,
          sellingUoms: [
            variantUom(
              id: 1,
              variantId: 1,
              price: 270,
              uomCode: unit,
              factor: factor,
              isWhole: factor == 1,
            ),
          ],
        ),
      ],
    ),
  ];
  final batches = [batch(id: 1, variantId: 1, qty: stock, cost: 200)];
  return PosTransactionViewmodel(
    InventoryViewmodel.seeded(
      catalogue: FakeProductsRepository(products: products, batches: batches),
      inventory: FakeInventoryRepository(),
      catalogueLists: FakeCatalogueRepository(),
      products: products,
      batches: batches,
      // Quantity is the server's on-hand read (Phase 9 F1); these lots are on the
      // home shelf, which is what a single-shelf server answers.
      stockOnHand: onHandFromBatches(batches),
    ),
  );
}

Future<void> _pumpBrowser(
  WidgetTester tester,
  List<PosCatalogItem> items,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 900,
          child: PosProductBrowser(
            products: items,
            searchController: TextEditingController(),
            searchFocusNode: FocusNode(),
            onSearch: (_) {},
            onSubmitted: (_) {},
            onSelect: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('a row built without the flag does not claim low stock', () {
    // Synthetic callers (held-cart restore, other screens' tests) build rows by
    // hand; the default must stay "not low" until the catalogue sets it.
    const item = PosCatalogItem(
      variantUomId: 1,
      variantId: 1,
      productName: 'Portland Cement',
      variantName: '40kg',
      unit: 'BAG',
      barcode: '',
      conversionFactor: 1,
      unitPrice: 270,
      availableBaseStock: 2,
    );

    expect(item.isLowStock, isFalse);
  });

  group('the catalogue carries the server verdict', () {
    test('base stock below the threshold is low', () {
      expect(
        _till(threshold: 10, stock: 8).filteredProducts.single.isLowStock,
        isTrue,
      );
    });

    test('base stock exactly at the threshold is NOT low', () {
      // The server compares `<`; `CatalogueItem.isLowStock` compares `<=`.
      expect(
        _till(threshold: 10, stock: 10).filteredProducts.single.isLowStock,
        isFalse,
      );
    });

    test('base stock above the threshold is not low', () {
      expect(
        _till(threshold: 10, stock: 11).filteredProducts.single.isLowStock,
        isFalse,
      );
    });

    test('a zero threshold never flags, however little is left', () {
      expect(
        _till(threshold: 0, stock: 1).filteredProducts.single.isLowStock,
        isFalse,
      );
    });

    test('the verdict is on base stock, not sale units', () {
      // 260 base = 10.4 boxes, which is above the old hardcoded 10 sale units
      // but still below the variant's 300 threshold.
      final till = _till(threshold: 300, stock: 260, factor: 25, unit: 'BOX');

      expect(till.filteredProducts.single.availableSaleQuantity, 10.4);
      expect(till.filteredProducts.single.isLowStock, isTrue);
    });
  });

  group('the badge shows the verdict', () {
    testWidgets('sale units above 10 are still low when base stock is below', (
      tester,
    ) async {
      final till = _till(threshold: 300, stock: 260, factor: 25, unit: 'BOX');

      await _pumpBrowser(tester, till.filteredProducts);

      expect(find.text('Low: 10.4 box left'), findsOneWidget);
      expect(
        find.text('10.4 box in stock'),
        findsNothing,
        reason: 'the hardcoded 10 compared SALE units against a base threshold',
      );
    });

    testWidgets('stock exactly at the variant threshold is not a warning', (
      tester,
    ) async {
      final till = _till(threshold: 10, stock: 10);

      await _pumpBrowser(tester, till.filteredProducts);

      expect(find.text('10 pc in stock'), findsOneWidget);
      expect(find.text('Low: 10 pc left'), findsNothing);
    });

    testWidgets('a zero threshold never warns', (tester) async {
      final till = _till(threshold: 0, stock: 3);

      await _pumpBrowser(tester, till.filteredProducts);

      expect(find.text('3 pc in stock'), findsOneWidget);
      expect(find.text('Low: 3 pc left'), findsNothing);
    });
  });
}
