import 'package:client/data/models/storage_location.dart';
import 'package:client/features/products/widgets/products_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live report (Linux desktop, 1280x720 window): "A RenderFlex overflowed by
/// 13/15 pixels on the right" on Products. The Category and Brand dropdowns
/// sit in narrow Expanded slots, and a DropdownButton sizes itself to its
/// WIDEST item unless `isExpanded` — so one long server-side category or brand
/// name broke the whole toolbar row.
///
/// Task 19 adds a THIRD dropdown ("Stock location") to the same row, which is
/// exactly the change that brings that overflow back if the row is not rebuilt.
Widget _toolbar(double width, {int? selectedStockLocationId}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: SizedBox(
        width: width,
        child: ProductsToolbar(
          searchQuery: '',
          categories: const ['Electrical Wiring, Lighting and Fixtures'],
          brands: const ['Pacific Paint (Boysen) Philippines Inc.'],
          selectedCategory: null,
          selectedBrand: null,
          stockLocations: const [
            StorageLocation(id: 1, name: 'Store'),
            StorageLocation(
              id: 2,
              name: 'Main Warehouse Extension, North Loading Bay',
            ),
            StorageLocation(id: 3, name: 'Old Shed', isActive: false),
          ],
          selectedStockLocationId: selectedStockLocationId,
          onSearchChanged: (_) {},
          onCategoryChanged: (_) {},
          onBrandChanged: (_) {},
          onStockLocationChanged: (_) {},
          onClearFilters: () {},
          onAddProduct: () {},
        ),
      ),
    ),
  ),
);

void main() {
  // 760 and 728 are the widths the card names: the narrow window the toolbar
  // has to survive without an overflow stripe. 1440 and 1100 are the desktop
  // windows the page is checked at with the Excel actions beside it.
  for (final width in [1440.0, 1100.0, 760.0, 728.0, 620.0, 460.0]) {
    testWidgets('long names fit the three-filter toolbar at ${width}px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_toolbar(width));

      expect(tester.takeException(), isNull);
      expect(find.text('Stock location'), findsOneWidget);
      expect(find.text('All locations'), findsOneWidget);
      expect(
        find.textContaining('stock available at the chosen location'),
        findsOneWidget,
        reason: 'the filter must say what it shows',
      );
    });
  }

  testWidgets('a chosen long location name stays inside the field at 760px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_toolbar(760, selectedStockLocationId: 2));

    expect(tester.takeException(), isNull);
    expect(find.text('Main Warehouse Extension, North Loading Bay'), findsOne);
  });

  testWidgets('a deactivated shelf is offered with its state said out loud', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_toolbar(1100, selectedStockLocationId: 3));

    expect(tester.takeException(), isNull);
    expect(find.text('Old Shed (inactive)'), findsOne);
  });
}
