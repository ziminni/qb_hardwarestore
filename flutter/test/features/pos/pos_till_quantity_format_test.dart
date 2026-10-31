// Card C1: the till renders quantities with the ONE app format.
//
// `formatQuantity` (lib/core/format/format.dart, D7) is what every other screen
// uses: a whole quantity is a count, a fractional one keeps at most two decimals
// with the trailing zeros dropped (`2.5`, not `2.50`). The till kept its own copy
// of the old rule in two places, so a part-metre sale read `2.50 sqm` in the cart
// and `38.50 sqm in stock` on the grid while the rest of the app said `2.5`.

import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_product_browser.dart';
import 'package:client/features/pos/widgets/pos_transaction_cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// One product sold by the square metre, because a fractional quantity is the
/// only case where the two formats differ at all.
List<Product> _products() => [
  product(
    id: 1,
    name: 'Marine Plywood',
    categoryName: 'Plywood',
    brandName: 'Cocofarm',
    variants: [
      variant(
        id: 1,
        productId: 1,
        name: '3/4 in x 4 x 8 ft',
        threshold: 5,
        baseUomCode: 'SQM',
        sellingUoms: [
          variantUom(id: 1, variantId: 1, price: 640, uomCode: 'SQM'),
        ],
      ),
    ],
  ),
];

List<InventoryBatch> _batches(double qty) => [
  batch(id: 1, variantId: 1, qty: qty, cost: 480),
];

PosTransactionViewmodel _till({double stock = 38.5}) {
  final products = _products();
  final batches = _batches(stock);
  return PosTransactionViewmodel(
    InventoryViewmodel.seeded(
      catalogue: FakeProductsRepository(products: products, batches: batches),
      inventory: FakeInventoryRepository(),
      catalogueLists: FakeCatalogueRepository(),
      products: products,
      batches: batches,
    ),
  );
}

Future<void> _pumpCart(
  WidgetTester tester,
  PosTransactionViewmodel till,
) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<PosTransactionViewmodel>.value(
      value: till,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 900,
            child: PosTransactionCart(
              onPayment: () {},
              onClear: () {},
              onChangeCustomer: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
  testWidgets('the cart shows a fractional line quantity as 2.5, not 2.50', (
    tester,
  ) async {
    final till = _till();
    final option = till.saleOptionsFor(till.filteredProducts.first).first;
    expect(till.addLine(option, 2.5), isNull);

    await _pumpCart(tester, till);

    expect(find.text('2.5 sqm'), findsOneWidget);
    expect(
      find.text('2.50 sqm'),
      findsNothing,
      reason: 'formatQuantity drops trailing zeros (D7); 2.50 is the old rule',
    );
  });

  testWidgets('a whole line quantity stays a plain count', (tester) async {
    final till = _till(stock: 400);
    final option = till.saleOptionsFor(till.filteredProducts.first).first;
    expect(till.addLine(option, 120), isNull);

    await _pumpCart(tester, till);

    expect(find.text('120 sqm'), findsOneWidget);
    expect(find.text('120.0 sqm'), findsNothing);
  });

  testWidgets('a fractional stock badge reads 38.5 sqm in stock', (
    tester,
  ) async {
    final item = PosCatalogItem(
      variantUomId: 1,
      variantId: 1,
      productName: 'Marine Plywood',
      variantName: '3/4 in x 4 x 8 ft',
      unit: 'SQM',
      barcode: '',
      conversionFactor: 1,
      unitPrice: 640,
      availableBaseStock: 38.5,
      categoryName: 'Plywood',
      brandName: 'Cocofarm',
    );

    await _pumpBrowser(tester, [item]);

    expect(find.text('38.5 sqm in stock'), findsOneWidget);
    expect(
      find.text('38.50 sqm in stock'),
      findsNothing,
      reason:
          'the grid keeps its own quantity rule; it must use formatQuantity',
    );
  });
}
