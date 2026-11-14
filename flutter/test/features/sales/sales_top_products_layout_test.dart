// Z2 fix task B (B-D2, D-09): the Top-selling products panel clipped its own
// rows.
//
// D-09: the ranked list sat in a fixed 170 px box, so a fourth product (and at
// text scale 1.3 the third product's "sold" line) fell outside the panel and was
// cut mid-row — the panel claimed to rank products it did not fully show.
//
// B-D2: a product name was one line with an ellipsis, so at text scale 1.3 the
// manager read "GI Sheet Plain 0.9mm x…" and lost which sheet it was.
//
// Both are measured on the REAL fonts at the panel's real width: 382 px is the
// 2/5 slot the dashboard gives this panel on a 1100 px window.
import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_top_products.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// The 2/5 slot the dashboard hands this panel on a 1100 px window.
const double panelWidth = 382;

/// Long names on purpose: these are the rows that ellipsized. The catalogue
/// prints a row as "base name + variant name", so the two are kept apart here
/// exactly as the products screen keeps them.
const List<(String, String)> products = [
  ('PVC Pipe', '4 inch x 3m'),
  ('Portland Cement', '50kg'),
  ('GI Sheet Plain', '0.9mm x 2.4m'),
  ('Electrical Wire', '2.0mm THHN'),
];

/// What each row reads: the name the panel resolves from the catalogue.
List<String> get productNames => [
  for (final (base, variant) in products) '$base $variant',
];

void main() {
  setUpAll(_loadRealFonts);

  testWidgets('every ranked product is fully inside the panel', (tester) async {
    await _pump(tester, textScale: 1.0);

    final panel = tester.getRect(find.byType(AppPanel));
    for (final name in productNames) {
      expect(
        find.text(name),
        findsOneWidget,
        reason: '"$name" was not laid out',
      );
      expect(
        tester.getRect(find.text(name)).bottom,
        lessThanOrEqualTo(panel.bottom),
        reason: '"$name" is cut by the card bottom',
      );
    }
    // The muted second line is what D-09 caught disappearing.
    for (final sold in [
      'PC · 12 sold',
      'PC · 6 sold',
      'PC · 3 sold',
      'PC · 1 sold',
    ]) {
      expect(
        find.text(sold),
        findsOneWidget,
        reason: '"$sold" was not laid out',
      );
      expect(
        tester.getRect(find.text(sold)).bottom,
        lessThanOrEqualTo(panel.bottom),
        reason: '"$sold" is cut by the card bottom',
      );
    }
  });

  testWidgets('a product name is not truncated at text scale 1.3', (
    tester,
  ) async {
    await _pump(tester, textScale: 1.3);

    const name = 'GI Sheet Plain 0.9mm x 2.4m';
    final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason:
          'the manager must read which sheet sold, not "GI Sheet Plain 0.9mm x…"',
    );
  });
}

Future<void> _pump(WidgetTester tester, {required double textScale}) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final inventory = _catalogue();
  await inventory.load();
  await tester.pumpWidget(
    ChangeNotifierProvider<InventoryViewmodel?>.value(
      value: inventory,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: panelWidth,
              child: SalesTopProducts(sales: _sales()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Four products, ranked by revenue: 12/6/3/1 sold at ₱450.00 a piece.
List<InventorySale> _sales() {
  const quantities = [12.0, 6.0, 3.0, 1.0];
  return [
    for (var index = 0; index < products.length; index++)
      InventorySale(
        transactionNo: 'TRX-20261102-000$index',
        date: DateTime(2026, 11, 2, 10, index),
        customer: 'Walk-in',
        cashier: 'Rosa Cruz',
        paymentMethod: 'Cash',
        source: 'Walk-in',
        status: InventorySaleStatus.completed,
        lines: [
          InventorySaleLine(
            variantUomId: 8 + index,
            // The wire carries the unit's code, never a name.
            productName: 'PC',
            variantName: 'PC',
            sku: 'PC',
            quantity: quantities[index],
            unitPrice: 450,
          ),
        ],
      ),
  ];
}

/// The catalogue the rows read their names from: one selling unit per product,
/// ids 8..11, matching the sales above.
InventoryViewmodel _catalogue() => InventoryViewmodel(
  products: FakeProductsRepository(
    products: [
      for (var index = 0; index < productNames.length; index++)
        product(
          id: index + 1,
          name: products[index].$1,
          categoryName: 'Plumbing',
          variants: [
            variant(
              id: index + 1,
              productId: index + 1,
              name: products[index].$2,
              sellingUoms: [
                variantUom(id: 8 + index, variantId: index + 1, price: 450),
              ],
            ),
          ],
        ),
    ],
    batches: [
      for (var index = 0; index < products.length; index++)
        batch(id: index + 1, variantId: index + 1, qty: 100),
    ],
  ),
  inventory: FakeInventoryRepository(),
  catalogue: FakeCatalogueRepository(),
);

/// The app's own fonts, so a truncation measured here is the truncation a
/// manager sees. The test fallback font is wider and would fail for the wrong
/// reason.
Future<void> _loadRealFonts() async {
  await _loadFont('Cinzel', const [
    'Cinzel-Regular.ttf',
    'Cinzel-Medium.ttf',
    'Cinzel-Bold.ttf',
  ]);
  await _loadFont('OpenSans', const [
    'OpenSans-Regular.ttf',
    'OpenSans-Medium.ttf',
    'OpenSans-Bold.ttf',
  ]);
}

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = await File('assets/fonts/$file').readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}
