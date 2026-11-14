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
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/views/products_page.dart';
import 'package:client/shared/widgets/app_dialog.dart';
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

/// Pumps the real page over a fake catalogue and hands back the repository, so
/// a test can assert which writes actually reached it.
Future<FakeProductsRepository> pumpProductsPage(
  WidgetTester tester, {
  required Size size,
  List<Product>? products,
  List<InventoryBatch>? batches,
  User? user,
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
          create: (_) =>
              AuthViewmodel(AuthRepository(AuthService()))..user = user,
        ),
        ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
      ],
      child: const MaterialApp(home: ProductsPage()),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('the whole page fits a 760 px window without an overflow', (
    tester,
  ) async {
    await pumpProductsPage(tester, size: const Size(760, 900));

    expect(tester.takeException(), isNull);
    expect(find.text('Products'), findsWidgets);
  });

  // Phase 2 F3 (decision 24): a merged account has no active area, so the
  // catalogue toolbar asks which areas it HOLDS. Stock Manager + Cashier keeps
  // the barcode list and the Phase 3 Excel round trip; a single Cashier is
  // unchanged and still offered none of them.
  group('catalogue actions follow the held areas', () {
    User account(List<String> roles) => User(
      id: 9,
      username: 'merged',
      email: 'merged@qb.ph',
      fullName: 'Ana Lopez',
      role: Role(id: 1, name: roles.first, displayName: roles.first),
      roles: [
        for (final (index, code) in roles.indexed)
          Role(id: index + 1, name: code, displayName: code),
      ],
    );

    testWidgets('a merged Stock and Cashier account keeps them', (tester) async {
      await pumpProductsPage(
        tester,
        size: const Size(2400, 1400),
        user: account(const ['inventory', 'pos']),
      );

      expect(find.text('Barcode list'), findsOneWidget);
      expect(find.text('Export to Excel'), findsOneWidget);
      expect(find.text('Import from Excel'), findsOneWidget);
    });

    testWidgets('a single Cashier account is still offered none', (
      tester,
    ) async {
      await pumpProductsPage(
        tester,
        size: const Size(2400, 1400),
        user: account(const ['pos']),
      );

      expect(find.text('Barcode list'), findsNothing);
      expect(find.text('Export to Excel'), findsNothing);
    });
  });

  // Phase 1d Task 7: the page used to hand the details dialog an invented
  // tracking configuration looked up by product NAME. "Portland Cement" is a
  // seeded name, so the dialog showed invented stock, weight and a Rack A-01
  // location that no server had ever sent.
  testWidgets('the details dialog tells nothing the server did not send', (
    tester,
  ) async {
    await pumpProductsPage(
      tester,
      size: const Size(1440, 1000),
      products: seededProducts(),
      batches: [batch(id: 1, variantId: 1, qty: 130)],
    );

    await tester.tap(find.byTooltip('View product').first);
    await tester.pumpAndSettle();

    expect(find.text('Inventory Tracking'), findsNothing);
    expect(find.textContaining('By Weight'), findsNothing);
    expect(find.textContaining('Rack A-01'), findsNothing);
  });

  testWidgets('the toolbar search is the shared FilterBar', (tester) async {
    await pumpProductsPage(tester, size: const Size(1440, 900));

    expect(find.byType(FilterBar), findsOneWidget);
  });

  testWidgets('the table view shows money in the one format and stock states '
      'as badges', (tester) async {
    await pumpProductsPage(tester, size: const Size(1440, 900));

    // D1: thousands separators and two decimals, right aligned with tabular
    // digits (DataPanel does the alignment from `numeric: true`). The price is
    // the BASE unit's and carries its unit, so a package row cannot pass its
    // money off as the base price (Phase 1d Task 9).
    expect(find.text('${formatPeso(1234567.89)} / BAG'), findsWidgets);
    expect(find.text('₱1,234,567.89 / BAG'), findsWidgets);
    expect(find.text('${formatPeso(315)} / PC'), findsWidgets);

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

  testWidgets('the price is the BASE unit\'s, with its unit, even when a '
      'package sorts first', (tester) async {
    // The server may answer [BAG (×40), KG (×1)]: list order is not identity.
    // The old caption took the first row, so this product would claim the bag's
    // ₱270 was the price of one kilogram.
    final packed = [
      product(
        id: 7,
        name: 'Tile Adhesive',
        categoryName: 'Cement',
        brandName: 'ABC',
        variants: [
          variant(
            id: 70,
            productId: 7,
            baseUomId: 2,
            baseUomCode: 'KG',
            sellingUoms: [
              variantUom(
                id: 701,
                variantId: 70,
                uomId: 3,
                uomCode: 'BAG',
                uomName: 'Bag',
                factor: 40,
                price: 270,
                isWhole: true,
              ),
              variantUom(
                id: 702,
                variantId: 70,
                uomId: 2,
                uomCode: 'KG',
                uomName: 'Kilogram',
                price: 6.75,
              ),
            ],
          ),
        ],
      ),
    ];
    await pumpProductsPage(
      tester,
      size: const Size(1440, 900),
      products: packed,
      batches: [batch(id: 1, variantId: 70, qty: 100)],
    );

    expect(find.text('₱6.75 / KG'), findsWidgets);
    expect(
      find.text('₱270.00 / BAG'),
      findsNothing,
      reason: 'the package price must not wear the base unit\'s caption',
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

  // Phase 1d Task 10a: the archive confirmations join the shared dialog family
  // (decision 17). The frame changes; the write does not, so the tests pin both
  // halves: the AppDialog shell, and that only a confirm PATCHes.
  testWidgets('the row archive confirmation is the shared dialog and only '
      'writes on confirm', (tester) async {
    final repository = await pumpProductsPage(
      tester,
      size: const Size(1440, 900),
    );

    await tester.tap(find.byTooltip('More actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to archive'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    // The question names the product it is about.
    expect(find.textContaining('Portland Cement'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(
      repository.activePatches,
      isEmpty,
      reason: 'Cancel must write nothing',
    );

    await tester.tap(find.byTooltip('More actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Move to archive'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(repository.activePatches.single.isActive, isFalse);
    expect(find.textContaining('moved to archive'), findsOneWidget);
  });

  testWidgets('the bulk archive confirmation is the shared dialog', (
    tester,
  ) async {
    final repository = await pumpProductsPage(
      tester,
      size: const Size(1440, 900),
    );

    await tester.tap(find.byKey(const ValueKey('ProductsRowSelect.2')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Move to archive'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Move to archive'));
    await tester.pumpAndSettle();

    expect(repository.activePatches.single.isActive, isFalse);
    expect(find.textContaining('moved to archive'), findsOneWidget);
  });
}
