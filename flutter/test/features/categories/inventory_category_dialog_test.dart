// Phase 1d Task 10a: the category dialog joins the shared dialog family
// (decision 17).
//
// The view is read-only (the server carries `{id, name, is_active}` and nothing
// else, so there is no description to edit and no Delete route); the edit mode
// renames and returns the trimmed name, exactly as before.

import 'package:client/data/models/product.dart';
import 'package:client/features/categories/widgets/inventory_category_dialog.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

void main() {
  testWidgets('the detail view opens in the shared frame and says the status '
      'in words', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryCategoryDialog(
            category: category(id: 1, name: 'Cement'),
            products: [product(id: 10, name: 'Portland Cement')],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Cement'), findsOneWidget);
    // Status is a word inside a badge, never colour alone.
    expect(find.byType(StatusBadge), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('PRODUCTS (1)'), findsOneWidget);
    expect(find.text('Portland Cement'), findsOneWidget);
  });

  testWidgets('an archived category says Archived in words', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InventoryCategoryDialog(
            category: category(id: 2, name: 'Plumbing', isActive: false),
            products: const [],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Archived'), findsWidgets);
    expect(find.text('No products in this category.'), findsOneWidget);
  });

  testWidgets('Edit renames in the shared frame and returns the trimmed name', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) => InventoryCategoryDialog(
                    category: category(id: 1, name: 'Cement'),
                    products: const <Product>[],
                    editing: true,
                  ),
                );
              },
              child: const Text('Rename'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Rename category'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Category name'),
      '  Cement and Aggregates  ',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(result, 'Cement and Aggregates');
    expect(find.byType(AppDialog), findsNothing);
  });

  testWidgets('Esc closes the category dialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => InventoryCategoryDialog(
                  category: category(id: 1, name: 'Cement'),
                  products: const [],
                ),
              ),
              child: const Text('View'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
  });
}
