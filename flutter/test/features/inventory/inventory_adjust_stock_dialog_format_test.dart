// Z1 (D18): the stock adjustment dialog writes its quantities as quantities.
//
// "Current system quantity: 1200" and "Difference: +50.0" leaked a raw double
// into copy the stock manager reads. formatQuantity (D7) is the app's one
// quantity rule, so a whole count is grouped and carries no decimals.

import 'package:client/features/inventory/widgets/inventory_adjust_stock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

Future<void> _pump(WidgetTester tester, {required double currentStock}) async {
  final item = product(id: 1);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: InventoryAdjustStockDialog(
          product: item,
          variant: item.variants.first,
          currentStock: currentStock,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a whole stock count is grouped and carries no decimals', (
    tester,
  ) async {
    await _pump(tester, currentStock: 1200);

    expect(find.text('Current system quantity: 1,200'), findsOneWidget);
    expect(
      find.text('Current system quantity: 1200.0'),
      findsNothing,
      reason: 'a raw double is not a quantity (formatQuantity, D7)',
    );
  });

  testWidgets('a difference carries its sign, grouped', (tester) async {
    await _pump(tester, currentStock: 1200);

    await tester.enterText(find.byType(TextFormField).first, '1250');
    await tester.pumpAndSettle();

    expect(find.text('Difference: +50'), findsOneWidget);
  });

  testWidgets('a fractional difference keeps one decimal, not two', (
    tester,
  ) async {
    await _pump(tester, currentStock: 10);

    await tester.enterText(find.byType(TextFormField).first, '7.5');
    await tester.pumpAndSettle();

    expect(find.text('Difference: -2.5'), findsOneWidget);
  });
}
