// Owner 2026-11-18: Admin → Settings → Categories & suppliers.
//
// Pinned: both lists show with their status; Add / Edit / Archive / Delete each
// send the right write; a refused delete shows the server's sentence and keeps
// the row; Delete is hidden from a non-Admin.

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/repositories/catalogue_repository.dart';
import 'package:client/data/repositories/supplier_repository.dart';
import 'package:client/data/services/catalogue_service.dart';
import 'package:client/features/admin/viewmodels/catalogue_lists_viewmodel.dart';
import 'package:client/features/admin/widgets/catalogue_lists_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeCategories extends CatalogueRepository {
  List<Category> rows = [
    const Category(id: 1, name: 'Cement'),
    const Category(id: 2, name: 'Paint', isActive: false),
  ];
  final calls = <String>[];
  String? refuseDelete;

  @override
  Future<List<Category>> fetchCategories() async => rows;

  @override
  Future<int> createCategory(String name) async {
    calls.add('create:$name');
    rows = [...rows, Category(id: 9, name: name)];
    return 9;
  }

  @override
  Future<void> patchCategory(int id, {String? name, bool? isActive}) async {
    calls.add('patch:$id:${name ?? ''}:${isActive ?? ''}');
  }

  @override
  Future<void> deleteCategory(int id) async {
    calls.add('delete:$id');
    if (refuseDelete != null) throw CatalogueServiceException(refuseDelete!);
    rows = [
      for (final row in rows)
        if (row.id != id) row,
    ];
  }
}

class _FakeSuppliers extends SupplierRepository {
  final calls = <String>[];

  @override
  Future<List<Supplier>> fetchSuppliers() async => const [
    Supplier(
      id: 5,
      companyName: 'Mactan Aggregates',
      contactPerson: 'Nonoy',
      phone: '0917',
      email: '',
      address: '',
      termsDays: 30,
    ),
  ];

  @override
  Future<void> patchSupplier(int id, Map<String, dynamic> body) async {
    calls.add('patch:$id:$body');
  }

  @override
  Future<void> deleteSupplier(int id) async => calls.add('delete:$id');
}

Future<(_FakeCategories, _FakeSuppliers)> _pump(
  WidgetTester tester, {
  bool canDelete = true,
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final categories = _FakeCategories();
  final suppliers = _FakeSuppliers();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: CatalogueListsPanel(
            canDelete: canDelete,
            viewmodel: CatalogueListsViewmodel(
              categories: categories,
              suppliers: suppliers,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (categories, suppliers);
}

void main() {
  testWidgets('both lists show, with active and archived rows', (tester) async {
    await _pump(tester);
    expect(find.text('Categories (2)'), findsOneWidget);
    expect(find.text('Suppliers (1)'), findsOneWidget);
    expect(find.text('Cement'), findsOneWidget);
    expect(find.text('Archived'), findsOneWidget);

    await tester.tap(find.text('Suppliers (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Mactan Aggregates'), findsOneWidget);
    expect(find.text('Nonoy · 0917 · Terms 30 days'), findsOneWidget);
  });

  testWidgets('add a category', (tester) async {
    final (categories, _) = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('add-category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('category-name')), 'Roof');
    await tester.tap(find.byKey(const ValueKey('category-save')));
    await tester.pumpAndSettle();
    expect(categories.calls, ['create:Roof']);
    expect(find.text('Roof'), findsOneWidget);
  });

  testWidgets('archive and edit send PATCHes', (tester) async {
    final (categories, _) = await _pump(tester);
    final cement = find.byKey(const ValueKey('category-1'));
    await tester.tap(
      find.descendant(of: cement, matching: find.byTooltip('Archive')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: cement, matching: find.byTooltip('Edit')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('category-name')),
      'Cement & Lime',
    );
    await tester.tap(find.byKey(const ValueKey('category-save')));
    await tester.pumpAndSettle();
    expect(categories.calls, ['patch:1::false', 'patch:1:Cement & Lime:']);
  });

  testWidgets('a refused delete shows why and keeps the row', (tester) async {
    final (categories, _) = await _pump(tester);
    categories.refuseDelete =
        'Cement is used by 12 products, so it cannot be deleted.';
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('category-1')),
        matching: find.byTooltip('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-action')));
    await tester.pumpAndSettle();
    expect(categories.calls, ['delete:1']);
    expect(find.textContaining('used by 12 products'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Cement'), findsOneWidget);
  });

  testWidgets('an unused category is deleted after confirming', (tester) async {
    final (categories, _) = await _pump(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('category-2')),
        matching: find.byTooltip('Delete'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-action')));
    await tester.pumpAndSettle();
    expect(categories.calls, ['delete:2']);
    expect(find.text('Paint'), findsNothing);
  });

  testWidgets('delete is hidden from a non-Admin', (tester) async {
    await _pump(tester, canDelete: false);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.byTooltip('Edit'), findsWidgets);
  });
}
