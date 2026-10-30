// Card K2 (ui-refresh): the Products page applies the shared look.
//
// What this locks, and why each one is written against the OLD code first:
//  1. The page fits a 760 px window. The catalog overview put a
//     "Click a metric to view related records" line in a Row beside the title,
//     so the narrow window overflowed before any of the new layout existed.
//  2. The table view is the shared DataPanel: money through `formatPeso`
//     (`₱1,234,567.89`, D1) right aligned with tabular digits, and the row's
//     stock state through `StatusBadge` (words plus color, never color alone).
//  3. Under 720 px of panel width the same view becomes cards instead of a
//     sideways-scrolling `DataTable`.
//  4. All FOUR view modes stay (D8): grid, list, table and compact table.
//  5. The Phase 6 entry points that hang off a row keep working in the new
//     table: the row menu's "Print labels" and the bulk selection toolbar.

import 'package:client/core/format/format.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:client/features/products/views/products_page.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// A catalogue shaped like the real one: a long product name, a long category
/// and brand, a 7 digit price (the widest money column), one low-stock variant
/// and one variant with no batch at all (out of stock).
List<Product> catalogue() => [
  product(
    id: 1,
    name: 'Portland Cement 40 kg bag, type 1P, pallet of 40 bags',
    categoryName: 'Cement and Aggregates',
    brandName: 'Holcim Philippines Incorporated',
    variants: [
      variant(
        id: 11,
        productId: 1,
        name: '40 kg bag',
        sellingUoms: [
          variantUom(
            id: 111,
            variantId: 11,
            price: 1234567.89,
            barcode: 'QB000011-2',
            uomCode: 'BAG',
          ),
        ],
      ),
    ],
  ),
  product(
    id: 2,
    name: 'Deformed Steel Bar 10 mm',
    categoryName: 'Steel bars',
    brandName: 'Steel Asia',
    variants: [
      variant(
        id: 22,
        productId: 2,
        name: '6 m length',
        threshold: 5,
        sellingUoms: [
          variantUom(
            id: 222,
            variantId: 22,
            price: 315,
            barcode: 'QB000022-3',
            uomCode: 'PC',
          ),
        ],
      ),
    ],
  ),
  product(
    id: 3,
    name: 'Marine Plywood 3/4 in',
    categoryName: 'Plywood',
    brandName: 'Coco Board',
    variants: [
      variant(
        id: 33,
        productId: 3,
        name: '4 x 8 sheet',
        sellingUoms: [
          variantUom(
            id: 333,
            variantId: 33,
            price: 1480.5,
            barcode: 'QB000033-1',
            uomCode: 'SHT',
          ),
        ],
      ),
    ],
  ),
];

List<InventoryBatch> stockBatches() => [
  batch(id: 1, variantId: 11, qty: 120),
  // Below its threshold of 5: low stock.
  batch(id: 2, variantId: 22, qty: 3),
  // Variant 33 has no batch on purpose: out of stock.
];

Future<void> pumpProductsPage(
  WidgetTester tester, {
  required Size size,
  List<Product>? products,
  List<InventoryBatch>? batches,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repository = FakeProductsRepository(
    products: products ?? catalogue(),
    batches: batches ?? stockBatches(),
  );
  final store = InventoryViewmodel(
    products: repository,
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        ),
        ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
        ChangeNotifierProvider(create: (_) => ProductTrackingViewmodel()),
      ],
      child: const MaterialApp(home: ProductsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the whole page fits a 760 px window without an overflow', (
    tester,
  ) async {
    await pumpProductsPage(tester, size: const Size(760, 900));

    expect(tester.takeException(), isNull);
    expect(find.text('Products'), findsWidgets);
  });

  testWidgets('the toolbar search is the shared FilterBar', (tester) async {
    await pumpProductsPage(tester, size: const Size(1440, 900));

    expect(find.byType(FilterBar), findsOneWidget);
  });

  testWidgets('the table view shows money in the one format and stock states '
      'as badges', (tester) async {
    await pumpProductsPage(tester, size: const Size(1440, 900));

    // D1: thousands separators and two decimals, right aligned with tabular
    // digits (DataPanel does the alignment from `numeric: true`).
    expect(find.text(formatPeso(1234567.89)), findsWidgets);
    expect(find.text('₱1,234,567.89'), findsWidgets);
    expect(find.text(formatPeso(315)), findsWidgets);

    expect(
      find.byType(StatusBadge),
      findsWidgets,
      reason: 'a stock state is words plus color, never a bare color',
    );
    expect(find.text('Low Stock'), findsOneWidget);
    expect(find.text('Out of Stock'), findsOneWidget);

    expect(find.byKey(const ValueKey('DataPanel.table')), findsOneWidget);
    expect(
      find.byType(DataTable),
      findsNothing,
      reason: 'the table view is the shared DataPanel, not a raw DataTable',
    );
  });

  testWidgets('at 760 the table view lays out as cards, not a sideways table', (
    tester,
  ) async {
    await pumpProductsPage(tester, size: const Size(760, 900));

    expect(find.byKey(const ValueKey('DataPanel.cards')), findsOneWidget);
    expect(find.byKey(const ValueKey('DataPanel.table')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a search that matches nothing keeps the filters and offers a '
      'way out', (tester) async {
    await pumpProductsPage(tester, size: const Size(760, 900));

    await tester.enterText(find.byType(TextField), 'NOT A PRODUCT');
    await tester.pumpAndSettle();

    expect(find.text('No products found'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Clear filters'),
      findsOneWidget,
      reason: 'an empty result must offer the way back to the full catalogue',
    );
  });

  testWidgets('all four view modes stay available (D8)', (tester) async {
    await pumpProductsPage(tester, size: const Size(1440, 900));

    for (final tooltip in const [
      'Grid view',
      'List view',
      'Table view',
      'Compact table',
    ]) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: '$tooltip lost');
    }

    await tester.tap(find.byTooltip('Grid view'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ProductsGrid')), findsOneWidget);

    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ProductsList')), findsOneWidget);

    await tester.tap(find.byTooltip('Compact table'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ProductsCompactTable')), findsOneWidget);

    await tester.tap(find.byTooltip('Table view'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('DataPanel.table')), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the row menu still prints labels and the selection bar still '
      'archives', (tester) async {
    await pumpProductsPage(tester, size: const Size(1440, 900));

    // Phase 6: printing labels from one row.
    await tester.tap(find.byTooltip('More actions').first);
    await tester.pumpAndSettle();
    expect(find.text('Print labels'), findsOneWidget);
    expect(find.text('Move to archive'), findsOneWidget);
    // Close the menu without printing.
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    // Phase 6: bulk selection keeps its own label print entry point. The row
    // checkbox, not the header's select-all.
    await tester.tap(find.byKey(const ValueKey('ProductsRowSelect.2')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Print labels'), findsOneWidget);
    expect(find.text('Clear selection'), findsOneWidget);
  });
}
