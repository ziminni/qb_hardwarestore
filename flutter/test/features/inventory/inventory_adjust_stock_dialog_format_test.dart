// Phase 1d Task 10a: the stock adjustment dialog joins the shared dialog family
// (decision 17).
//
// Two things this dialog has to get right, both pinned here:
//  - the quantities are QUANTITIES, written through formatQuantity (D7), never a
//    raw double. "Current system quantity: 1200" and "Difference: +50.0" leaked
//    a raw double into copy the stock manager reads (Z1 / D18);
//  - the difference is said IN WORDS ("Increase by 50"), not by colour alone.

import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_adjust_stock_dialog.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  testWidgets('the dialog opens in the shared dialog frame', (tester) async {
    await _pump(tester, currentStock: 1200);

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Adjust Stock'), findsOneWidget);
  });

  testWidgets('system and new quantities sit side by side as boxes', (
    tester,
  ) async {
    await _pump(tester, currentStock: 1200);

    expect(find.text('SYSTEM QUANTITY'), findsOneWidget);
    expect(find.text('NEW QUANTITY'), findsOneWidget);

    // The system figure is a quantity (grouped, no decimals), not a raw double.
    // The boxes draw each figure in one rich line with its unit, and before a
    // count is typed both boxes read the same number.
    expect(find.text('1,200  PC', findRichText: true), findsNWidgets(2));
    expect(
      find.text('Current system quantity: 1200.0'),
      findsNothing,
      reason: 'a raw double is not a quantity (formatQuantity, D7)',
    );
  });

  testWidgets('an increase is said in words, not by colour alone', (
    tester,
  ) async {
    await _pump(tester, currentStock: 1200);

    await tester.enterText(find.byType(TextFormField).first, '1250');
    await tester.pumpAndSettle();

    expect(find.text('Increase by 50'), findsOneWidget);
    expect(find.byType(StatusBadge), findsOneWidget);
    expect(
      find.text('Difference: +50.0'),
      findsNothing,
      reason: 'the difference is a quantity, and it is worded',
    );
  });

  testWidgets('a fractional decrease keeps one decimal, not two', (
    tester,
  ) async {
    await _pump(tester, currentStock: 10);

    await tester.enterText(find.byType(TextFormField).first, '7.5');
    await tester.pumpAndSettle();

    expect(find.text('Decrease by 2.5'), findsOneWidget);
  });

  testWidgets('an unchanged count says so instead of showing a zero', (
    tester,
  ) async {
    await _pump(tester, currentStock: 10);

    expect(find.text('No change'), findsOneWidget);
  });

  testWidgets('a fractional system count is not rounded in the field', (
    tester,
  ) async {
    await _pump(tester, currentStock: 7.5);

    expect(
      find.widgetWithText(TextFormField, '7.5'),
      findsOneWidget,
      reason: 'the field must start at the real count, not at 8',
    );
    expect(find.text('7.5  PC', findRichText: true), findsNWidgets(2));
  });

  testWidgets('the confirm button still returns the adjusted quantity', (
    tester,
  ) async {
    InventoryAdjustStockResult? result;
    final item = product(id: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<InventoryAdjustStockResult>(
                  context: context,
                  builder: (_) => InventoryAdjustStockDialog(
                    product: item,
                    variant: item.variants.first,
                    currentStock: 10,
                  ),
                );
              },
              child: const Text('Adjust'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Adjust'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '25');
    await tester.tap(find.text('Confirm Adjustment'));
    await tester.pumpAndSettle();

    expect(result?.quantity, 25);
  });

  // Phase 8 F2 (decision 20): goods must go back through the supplier return
  // flow, which takes them off the RECEIPT's batches and mints a credit note. A
  // bare RETURN adjustment moves stock and credits nobody, so the server now
  // refuses it (`USE_SUPPLIER_RETURN`) and the dialog stops offering it.
  testWidgets('the reason list no longer offers a supplier return', (
    tester,
  ) async {
    await _pump(tester, currentStock: 10);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(
      find.text('Supplier Return'),
      findsNothing,
      reason: 'the client cannot ask for a RETURN the server refuses',
    );
    for (final reason in [
      'Count Correction',
      'Damaged Items',
      'Shrinkage / Loss',
    ]) {
      expect(find.text(reason), findsWidgets);
    }
  });

  testWidgets('the offered reasons are the viewmodel\'s one list', (
    tester,
  ) async {
    expect(InventoryViewmodel.adjustmentReasons, const [
      'Count Correction',
      'Damaged Items',
      'Shrinkage / Loss',
    ]);
  });

  testWidgets('Esc closes the dialog without a result', (tester) async {
    InventoryAdjustStockResult? result;
    var popped = false;
    final item = product(id: 1);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<InventoryAdjustStockResult>(
                  context: context,
                  builder: (_) => InventoryAdjustStockDialog(
                    product: item,
                    variant: item.variants.first,
                    currentStock: 10,
                  ),
                );
                popped = true;
              },
              child: const Text('Adjust'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Adjust'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(result, isNull);
    expect(find.byType(AppDialog), findsNothing);
  });
}
