// K5 / D2: this screen is "Stock adjustments", and says only what it knows.
//
// The screen reads `GET /api/v1/adjustments/`, and an adjustment is only ever
// Shrinkage / Loss, Damaged, Count correction or Return to supplier. Yet it was
// titled "Stock Movements" with "STOCK IN" / "STOCK OUT" totals, incoming and
// outgoing tabs, a Stock Balance tab and Previous / New columns whose values the
// server never sends (`StockAdjustmentSerializer` carries a delta, not a
// before/after pair), so those cells were dashes or invented zeros.
//
// The contract pinned here:
//   * the title, and the menu entry that leads to it, say "Stock adjustments"
//   * no "stock in" / "stock out" wording and no before/after columns survive
//   * a row shows its type in words, a signed quantity, the reason, who and when
//   * the type chips filter the list, and the two empty states differ
//   * a long history builds its rows lazily, with no pager controls

import 'package:client/core/format/format.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_stock_movements_page.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// The empty copy of a completed load: one for "nothing recorded in this
/// period", one for "the filters hide everything".
const _nothingRecorded = 'No adjustments recorded for this period.';
const _noMatch = 'No adjustments match these filters.';

StockAdjustment _adjustment({
  int id = 1,
  int variantId = 1,
  int userId = 7,
  StockAdjustmentType type = StockAdjustmentType.damage,
  double quantity = -2,
  String remarks = 'Cracked casing.',
  DateTime? timestamp,
}) => StockAdjustment(
  id: id,
  variantId: variantId,
  userId: userId,
  adjustmentType: type,
  quantityAdjusted: quantity,
  remarks: remarks,
  // Inside the page's default "this month" period.
  timestamp: timestamp ?? DateTime.now().subtract(const Duration(hours: 1)),
);

List<Product> _catalogue() => [
  product(
    id: 1,
    name: 'Portland Cement',
    categoryName: 'Cement',
    variants: [
      variant(
        id: 1,
        productId: 1,
        name: '40 kg bag',
        threshold: 30,
        baseUomCode: 'BAG',
      ),
    ],
  ),
  product(
    id: 2,
    name: 'Deformed Steel Bar 10 mm x 6 m Grade 60',
    categoryName: 'Steel bars',
    variants: [
      variant(
        id: 2,
        productId: 2,
        name: '10 mm x 6 m',
        threshold: 80,
        baseUomCode: 'PC',
      ),
    ],
  ),
];

InventoryViewmodel _store({List<StockAdjustment> adjustments = const []}) {
  final products = _catalogue();
  return InventoryViewmodel(
    products: FakeProductsRepository(products: products),
    inventory: FakeInventoryRepository(adjustments: adjustments),
    catalogue: FakeCatalogueRepository(),
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  InventoryViewmodel store, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewmodel>(
          create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        ),
        ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
      ],
      child: MaterialApp(home: const InventoryStockMovementsPage()),
    ),
  );
  await store.load();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the page and its menu entry are called Stock adjustments', (
    tester,
  ) async {
    await _pumpPage(tester, _store(adjustments: [_adjustment()]));

    expect(find.text('Stock Movements'), findsNothing);
    expect(find.text('Stock movements'), findsNothing);
    // The header title and the menu entry that opens it.
    expect(find.text('Stock adjustments'), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(SharedSidebar),
        matching: find.text('Stock adjustments'),
      ),
      findsOneWidget,
      reason: 'D2 renames the label; the index and route stay',
    );
  });

  testWidgets('no stock in, stock out or before/after wording survives', (
    tester,
  ) async {
    await _pumpPage(tester, _store(adjustments: [_adjustment()]));

    for (final gone in [
      'STOCK IN',
      'STOCK OUT',
      'TOTAL MOVEMENTS',
      'Stock In',
      'Stock Out',
      'All Movements',
      'Stock Balance',
      'Previous',
      'New',
    ]) {
      expect(
        find.text(gone),
        findsNothing,
        reason: '"$gone" was a direction or a figure this screen cannot show',
      );
    }
  });

  testWidgets('a row says what happened, how much, why, who and when', (
    tester,
  ) async {
    final when = DateTime.now().subtract(const Duration(hours: 3));
    await _pumpPage(
      tester,
      _store(
        adjustments: [
          _adjustment(
            type: StockAdjustmentType.damage,
            quantity: -2,
            remarks: 'Cracked casing.',
            userId: 7,
            timestamp: when,
          ),
        ],
      ),
    );

    expect(find.textContaining('Portland Cement'), findsOneWidget);
    expect(find.text('40 kg bag'), findsOneWidget);
    expect(find.text('-2 BAG'), findsOneWidget);
    expect(find.text('Cracked casing.'), findsOneWidget);
    expect(find.text('User 7'), findsOneWidget);
    expect(find.text(formatDateTime(when)), findsOneWidget);
    // The type as a word, in a pill, not a direction arrow.
    expect(
      find.descendant(
        of: find.byType(StatusBadge),
        matching: find.text('Damaged'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the type chips filter the list and All types restores it', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      _store(
        adjustments: [
          _adjustment(id: 1, remarks: 'Cracked casing.'),
          _adjustment(
            id: 2,
            type: StockAdjustmentType.correction,
            quantity: 1,
            remarks: 'Recount at the yard.',
          ),
        ],
      ),
    );

    expect(find.text('Cracked casing.'), findsOneWidget);
    expect(find.text('Recount at the yard.'), findsOneWidget);

    // Scoped to the bar: the chip label equals the row's badge label.
    await tester.tap(
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('Count Correction'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recount at the yard.'), findsOneWidget);
    expect(find.text('Cracked casing.'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('All types'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cracked casing.'), findsOneWidget);
    expect(find.text('Recount at the yard.'), findsOneWidget);
  });

  testWidgets('nothing recorded and nothing matching read differently', (
    tester,
  ) async {
    await _pumpPage(tester, _store(adjustments: [_adjustment()]));

    expect(find.text(_nothingRecorded), findsNothing);
    expect(find.text(_noMatch), findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pumpAndSettle();

    expect(find.text(_noMatch), findsOneWidget);
    expect(find.text(_nothingRecorded), findsNothing);
  });

  testWidgets('a period with no adjustments says so, without a search', (
    tester,
  ) async {
    await _pumpPage(tester, _store());

    expect(find.text(_nothingRecorded), findsOneWidget);
    expect(find.text(_noMatch), findsNothing);
  });

  testWidgets('a long history scrolls, built row by row, with no pager', (
    tester,
  ) async {
    final rows = [
      for (var index = 0; index < 60; index++)
        _adjustment(
          id: index + 1,
          remarks: 'Row $index remark.',
          timestamp: DateTime.now().subtract(Duration(hours: index + 1)),
        ),
    ];
    await _pumpPage(
      tester,
      _store(adjustments: rows),
      size: const Size(1100, 900),
    );

    expect(find.text('Row 0 remark.'), findsOneWidget);
    expect(
      find.text('Row 59 remark.'),
      findsNothing,
      reason: 'the last of 60 rows is not built until it is scrolled to',
    );
    expect(find.text('10 rows'), findsNothing, reason: 'no pager controls');

    await tester.scrollUntilVisible(
      find.text('Row 59 remark.'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('DataPanel.table')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Row 59 remark.'), findsOneWidget);
  });
}
