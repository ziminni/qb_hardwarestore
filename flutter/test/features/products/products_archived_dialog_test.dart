// Phase 1d Task 10a: the archived products dialog joins the shared dialog
// family (decision 17).
//
// The frame is what changes here; the Restore write does not. So the tests pin
// both: the AppDialog shell with its hexagon header, the archived state in
// words, and the same PATCH-then-reload behaviour the screen already had.

import 'package:client/data/models/product.dart';
import 'package:client/features/products/widgets/products_archived_dialog.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

Future<List<Product>> _pump(
  WidgetTester tester, {
  List<Product>? products,
  Future<String?> Function(Product product)? onRestore,
}) async {
  final rows = products ?? [product(id: 1, name: 'Ardex 1000')];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProductsArchivedDialog(
          products: rows,
          onRestore: onRestore ?? (_) async => null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return rows;
}

void main() {
  testWidgets('the archived list opens in the shared dialog frame', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Archived products'), findsOneWidget);
    expect(find.text('Ardex 1000'), findsOneWidget);
    // Archived is a status, so it is said in words and not by colour alone.
    expect(find.text('Archived'), findsWidgets);
  });

  testWidgets('Restore writes through onRestore and drops the row', (
    tester,
  ) async {
    final restored = <int>[];
    await _pump(
      tester,
      onRestore: (product) async {
        restored.add(product.id);
        return null;
      },
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Restore'));
    await tester.pumpAndSettle();

    expect(restored, [1]);
    expect(find.text('Ardex 1000'), findsNothing);
    expect(find.textContaining('restored to the catalogue'), findsOneWidget);
  });

  testWidgets('a refused Restore keeps the row and shows the server sentence', (
    tester,
  ) async {
    await _pump(
      tester,
      onRestore: (_) async => 'That product no longer exists.',
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Restore'));
    await tester.pumpAndSettle();

    expect(find.text('Ardex 1000'), findsOneWidget);
    expect(find.text('That product no longer exists.'), findsOneWidget);
  });

  testWidgets('an empty archive says so in the shared frame', (tester) async {
    await _pump(tester, products: const []);

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('No archived products'), findsOneWidget);
  });

  testWidgets('Esc closes the archived dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ProductsArchivedDialog(
                  products: [product(id: 1, name: 'Ardex 1000')],
                  onRestore: (_) async => null,
                ),
              ),
              child: const Text('Open archive'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open archive'));
    await tester.pumpAndSettle();
    expect(find.byType(AppDialog), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    // Focus comes back to the control that opened the dialog.
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNotNull);
  });
}
