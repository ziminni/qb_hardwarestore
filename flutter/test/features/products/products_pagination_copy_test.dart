// Z1 (D18): the products page range is words, not an en dash.
//
// "Showing 1–20 of 80 products" was the last en dash in visible copy. The
// reader gets the same fact with "to", and a screen reader no longer reads
// "one en dash twenty".

import 'package:client/features/products/widgets/products_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  required int firstItem,
  required int lastItem,
  required int totalItems,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: ProductsPagination(
        firstItem: firstItem,
        lastItem: lastItem,
        totalItems: totalItems,
        currentPage: 1,
        totalPages: 4,
        rowsPerPage: 20,
        onPageChanged: (_) {},
        onRowsPerPageChanged: (_) {},
      ),
    ),
  ),
);

void main() {
  testWidgets('a page range reads "Showing 1 to 20 of 80 products"', (
    tester,
  ) async {
    await _pump(tester, firstItem: 1, lastItem: 20, totalItems: 80);

    expect(find.text('Showing 1 to 20 of 80 products'), findsOneWidget);
    expect(find.text('Showing 1–20 of 80 products'), findsNothing);
  });

  testWidgets('an empty list still says 0 products', (tester) async {
    await _pump(tester, firstItem: 0, lastItem: 0, totalItems: 0);

    expect(find.text('0 products'), findsOneWidget);
  });
}
