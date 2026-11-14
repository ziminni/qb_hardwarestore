// Phase 1d Task 5 (decision 16): the whole-number rule comes from the SERVER.
//
// Until 1d, `lib/core/units/whole_units.dart` held a hardcoded list of unit
// words (`pc`, `bag`, `box`, ...). The server enforces the rule with a flag on
// each unit, so the list had to go: it cannot answer for a shop that flags `PC`
// as measured, and it invented a refusal for a `QABUNDLE` sold in ones.
//
// Both directions are asserted, because a test that only proves "PC is whole"
// would still pass with the deleted list.

import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/pos/widgets/pos_sale_quantity_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PosCatalogItem _item({
  required String unit,
  required bool isWhole,
  double price = 20,
}) => PosCatalogItem(
  variantUomId: 1,
  variantId: 1,
  productName: 'Tile Adhesive',
  variantName: 'Standard',
  unit: unit,
  barcode: 'QB000060-1',
  conversionFactor: 1,
  unitPrice: price,
  availableBaseStock: 100,
  isWhole: isWhole,
);

Future<void> _pumpDialog(WidgetTester tester, PosCatalogItem item) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PosSaleQuantityDialog(product: item, options: [item]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Types a quantity and asks the form to validate it the way the Add button does.
Future<void> _enterAndSubmit(WidgetTester tester, String quantity) async {
  await tester.enterText(find.byType(TextFormField), quantity);
  await tester.tap(find.text('Add to cart'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a unit the server flagged whole refuses a fractional count', (
    tester,
  ) async {
    await _pumpDialog(tester, _item(unit: 'SQM', isWhole: true));

    await _enterAndSubmit(tester, '1.5');

    expect(
      find.text('Use a whole number for SQM'),
      findsOneWidget,
      reason:
          'the flag is what the server enforces, so a whole-flagged unit the '
          'client has never heard of must still be refused',
    );
  });

  testWidgets('a unit coded PC but flagged measured ACCEPTS 1.5', (
    tester,
  ) async {
    await _pumpDialog(tester, _item(unit: 'PC', isWhole: false));

    await _enterAndSubmit(tester, '1.5');

    expect(
      find.text('Use a whole number for PC'),
      findsNothing,
      reason:
          'the deleted client list called every PC whole; the server flag says '
          'this shop sells it by length, so 1.5 is a real quantity',
    );
  });

  testWidgets('a measured unit still has to be more than nothing', (
    tester,
  ) async {
    await _pumpDialog(tester, _item(unit: 'KG', isWhole: false));

    await _enterAndSubmit(tester, '0');

    expect(find.text('Enter a valid quantity'), findsOneWidget);
  });
}
