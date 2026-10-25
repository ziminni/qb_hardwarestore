import 'package:client/features/products/widgets/products_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Live report (Linux desktop, 1280x720 window): "A RenderFlex overflowed by
/// 13/15 pixels on the right" on Products. The Category and Brand dropdowns
/// sit in narrow Expanded slots, and a DropdownButton sizes itself to its
/// WIDEST item unless `isExpanded` — so one long server-side category or brand
/// name broke the whole toolbar row.
Widget _toolbar(double width) => MaterialApp(
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
          onSearchChanged: (_) {},
          onCategoryChanged: (_) {},
          onBrandChanged: (_) {},
          onClearFilters: () {},
          onAddProduct: () {},
          onOpenSimulator: () {},
        ),
      ),
    ),
  ),
);

void main() {
  for (final width in [1000.0, 1060.0, 1400.0]) {
    testWidgets('long category and brand names fit the toolbar at ${width}px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_toolbar(width));

      expect(tester.takeException(), isNull);
    });
  }
}
