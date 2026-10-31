// K4 (UI refresh): the Stock screen is read and adjusted from a table that has
// to stay usable on a laptop.
//
// What the plan (temp/ui-refresh/03-stock-manager/04-stock.md) and the card say,
// and what each test below pins:
//   * "Adjust" is visible and tappable at 1100 px. Ten columns pushed the button
//     off the right edge, so the one action on the row needed a sideways scroll
//     nobody discovers.
//   * The storage location is a note kept on THIS computer (D9), so its column
//     and its filter say so instead of looking like shared server data.
//   * Sort labels carry no dashes (D18): "Name A to Z" and "Name Z to A".
//   * The list itself is the shared DataPanel (table at 1440, cards under 720),
//     statuses are StatusBadges and the filters are a FilterBar, so this screen
//     stops drifting from the rest of the app.

import 'dart:convert';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_stock_page.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// The note stored on this device for the first seeded variant.
const _shelfNote = 'Shelf G-02';

/// The empty copy the page has always used; it stays verbatim because
/// `inventory_stock_pages_load_test.dart` pins it.
const _stockEmpty = 'No stock records match these filters.';

void main() {
  /// Two variants in stock (130 and 40 on hand), one shelf note on the device.
  Future<InventoryViewmodel> storeWithShelfNote() async {
    SharedPreferences.setMockInitialValues({
      'stock_location_hints': jsonEncode({'1': _shelfNote}),
    });
    final store = seededInventory();
    await store.loadLocationHints();
    return store;
  }

  Future<void> pumpStock(
    WidgetTester tester,
    InventoryViewmodel store, {
    Size size = const Size(1100, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>(
            create: (_) => AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: const InventoryStockPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Adjust is visible and opens the dialog at 1100 px', (
    tester,
  ) async {
    final store = await storeWithShelfNote();
    await pumpStock(tester, store);

    final adjust = find.widgetWithText(OutlinedButton, 'Adjust');
    expect(adjust, findsWidgets, reason: 'one Adjust per row');

    // Visible means inside the window, not merely built: the old table built
    // every cell and scrolled the last ones out of sight.
    for (final element in adjust.evaluate()) {
      final rect = tester.getRect(find.byElementPredicate((e) => e == element));
      expect(
        rect.right,
        lessThanOrEqualTo(1100),
        reason: 'the Adjust button must not sit past the right edge',
      );
    }
    expect(adjust.hitTestable(), findsWidgets);

    await tester.tap(adjust.first);
    await tester.pumpAndSettle();
    expect(find.text('Adjust Stock'), findsOneWidget);
  });

  testWidgets(
    'the device only location is labelled "Shelf note (this computer)"',
    (tester) async {
      final store = await storeWithShelfNote();
      await pumpStock(tester, store);

      expect(find.text('Shelf note (this computer)'), findsOneWidget);

      // The note itself lives in the row details, not in a shared-looking column.
      await tester.tap(find.text('Portland Cement').first);
      await tester.pumpAndSettle();
      expect(find.text(_shelfNote), findsOneWidget);
      expect(find.text('Barcode'), findsOneWidget);
    },
  );

  testWidgets('sort labels carry no dash', (tester) async {
    final store = await storeWithShelfNote();
    await pumpStock(tester, store);

    expect(find.text('Name A to Z'), findsOneWidget);
    await tester.tap(find.text('Name A to Z'));
    await tester.pumpAndSettle();
    expect(find.text('Name Z to A'), findsOneWidget);

    expect(find.textContaining('–'), findsNothing);
    expect(find.textContaining('—'), findsNothing);
  });

  testWidgets('the list is a DataPanel with StatusBadges and a FilterBar', (
    tester,
  ) async {
    final store = await storeWithShelfNote();
    await pumpStock(tester, store, size: const Size(1440, 900));

    expect(find.byType(FilterBar), findsOneWidget);
    expect(find.byKey(const ValueKey('DataPanel.table')), findsOneWidget);
    expect(find.byType(StatusBadge), findsNWidgets(2));
    // Barcode, unit and shelf note moved into the row details, so the table
    // keeps only the columns that answer "how much is left".
    expect(find.text('Barcode'), findsNothing);
  });

  testWidgets('status chips filter the rows', (tester) async {
    final store = await storeWithShelfNote();
    await pumpStock(tester, store);

    await tester.tap(find.text('Out of stock'));
    await tester.pumpAndSettle();
    expect(find.text(_stockEmpty), findsOneWidget);

    await tester.tap(find.text('In stock'));
    await tester.pumpAndSettle();
    expect(find.text('Portland Cement'), findsOneWidget);
  });

  testWidgets('under 720 px of content the rows become cards', (tester) async {
    final store = await storeWithShelfNote();
    // 760 px window, compact shell: 712 px of content, below the 720 breakpoint.
    await pumpStock(tester, store, size: const Size(760, 900));

    expect(find.byKey(const ValueKey('DataPanel.cards')), findsOneWidget);
    expect(find.text('Adjust'), findsWidgets);
  });
}
