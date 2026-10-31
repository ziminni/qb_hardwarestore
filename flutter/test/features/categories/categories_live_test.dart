// Phase 4 Task 4 — categories, live.
//
// The screen is the one Phase 3 explicitly deferred: it snackbarred
// "Category updated in mock data." on a rename that only touched a list in the
// viewmodel. Now every action reaches `/api/v1/categories/` and reloads, and there
// is no Delete — the route answers 405, so archive and restore are the same PATCH
// with the other flag.
//
// The last test is a GREP, not a widget assertion: the phrase "mock data" is how
// the old screen admitted the lie, and it must not come back anywhere under lib/.

import 'dart:io';

import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/categories/views/categories_page.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../no_dead_controls_test.dart' show stripDartComments;
import '../../support/phase4_fakes.dart';

void main() {
  late _FlakyProductsRepository products;
  late FakeCatalogueRepository catalogue;
  late InventoryViewmodel inventory;

  setUp(() {
    products = _FlakyProductsRepository();
    catalogue = FakeCatalogueRepository(
      categories: [
        category(id: 1, name: 'Cement'),
        category(id: 2, name: 'Plumbing', isActive: false),
      ],
      brands: const [Brand(id: 1, name: 'Holcim')],
      units: const [UnitOfMeasure(id: 1, code: 'BAG', name: 'Bag')],
    );
    inventory = InventoryViewmodel(
      products: products,
      inventory: FakeInventoryRepository(),
      catalogue: catalogue,
    );
  });

  Future<void> pumpPage(WidgetTester tester) async {
    // The page reads the store and, if it was never loaded, fetches on open —
    // the same path the live screen takes when the app opens on Categories.
    await inventory.load();
    tester.view.physicalSize = const Size(2000, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>(
            create: (_) => AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
        ],
        child: const MaterialApp(home: CategoriesPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A chip label lives in the filter bar; the same word may also be a status
  /// badge on a card below it, so every chip tap is scoped to the bar.
  Finder chip(String label) =>
      find.descendant(of: find.byType(FilterBar), matching: find.text(label));

  testWidgets('creating a category POSTs it and the reload shows it', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.tap(find.text('New category'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Category name'),
      'Roofing',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(catalogue.createdCategories, ['Roofing']);
    // Read back from the store, which the write reloaded: the card is the proof
    // that the change came from the server rather than from a local list.
    expect(inventory.categories.map((c) => c.name), contains('Roofing'));
    expect(find.text('Roofing'), findsOneWidget);
  });

  testWidgets('archiving a category PATCHes is_active=false', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Category actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Archive'));
    await tester.pumpAndSettle();

    expect(catalogue.categoryPatches.single.id, 1);
    expect(catalogue.categoryPatches.single.isActive, isFalse);
    expect(inventory.categories.firstWhere((c) => c.id == 1).isActive, isFalse);
  });

  testWidgets('an archived category offers Restore, which PATCHes it back', (
    tester,
  ) async {
    await pumpPage(tester);

    // The Plumbing card is the archived one; its menu says Restore, not Archive.
    await tester.tap(find.byTooltip('Category actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(catalogue.categoryPatches.single.id, 2);
    expect(catalogue.categoryPatches.single.isActive, isTrue);
    expect(inventory.categories.firstWhere((c) => c.id == 2).isActive, isTrue);
  });

  testWidgets('a refused rename shows the server message and keeps the name', (
    tester,
  ) async {
    await pumpPage(tester);
    catalogue.writeError = 'category with this name already exists.';

    await tester.tap(find.byTooltip('Category actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Category name'),
      'Cement',
    );
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(
      find.text('category with this name already exists.'),
      findsOneWidget,
    );
    expect(inventory.categories.firstWhere((c) => c.id == 1).name, 'Cement');
  });

  // K3: a card that does not say how many products sit under a category makes
  // archiving a blind choice. The number comes from the catalogue the store
  // already loaded (every page of it), never from a new endpoint.
  testWidgets('each card counts the products filed under its category', (
    tester,
  ) async {
    products.setProducts([
      product(id: 10, name: 'Portland Cement 40kg', categoryId: 1),
      product(id: 11, name: 'Portland Cement 25kg', categoryId: 1),
      product(id: 12, name: 'Masonry Cement', categoryId: 1),
      product(id: 20, name: 'PVC Pipe 1/2 inch', categoryId: 2),
    ]);

    await pumpPage(tester);

    expect(find.text('3 products'), findsOneWidget);
    expect(find.text('1 product'), findsOneWidget);
  });

  // A failed reload must not throw the cards away: they are the last thing the
  // server said, and the banner above them says why they may be stale.
  testWidgets('a failed refresh keeps the cards under one retry banner', (
    tester,
  ) async {
    await pumpPage(tester);
    products.fail = true;

    await inventory.load();
    await tester.pumpAndSettle();

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('Cement'), findsOneWidget);
    expect(find.text('Plumbing'), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
  });

  // The other half of the rule: with nothing loaded there is one failure and no
  // empty state under it, because "no categories" is the one thing a failed
  // fetch has not established.
  testWidgets('a failed first load shows one failure and no empty state', (
    tester,
  ) async {
    products.fail = true;

    await pumpPage(tester);

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(EmptyState), findsNothing);
  });

  testWidgets('the Archived chip narrows the grid to archived categories', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.text('Cement'), findsOneWidget);
    expect(find.text('Plumbing'), findsOneWidget);

    await tester.tap(chip('Archived'));
    await tester.pumpAndSettle();

    expect(find.text('Plumbing'), findsOneWidget);
    expect(find.text('Cement'), findsNothing);

    await tester.tap(chip('Active'));
    await tester.pumpAndSettle();

    expect(find.text('Cement'), findsOneWidget);
    expect(find.text('Plumbing'), findsNothing);
  });

  // "No categories yet" and "no categories match" are different facts, and the
  // old screen said the second one for both.
  testWidgets('an empty catalogue says there are no categories yet', (
    tester,
  ) async {
    catalogue.setCategories(const []);

    await pumpPage(tester);

    expect(find.text('No categories yet.'), findsOneWidget);
    expect(find.text('No categories match these filters.'), findsNothing);
  });

  test('no screen claims a change lives in mock data', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      // Comments are stripped first: a code comment that explains what the mock
      // era did is documentation, while a SnackBar or label saying it is a lie
      // still on screen.
      final code = stripDartComments(file.readAsStringSync()).toLowerCase();
      if (code.contains('mock data') ||
          code.contains('mock inventory') ||
          code.contains('mock catalogue')) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'A clerk-facing string that says a change was applied to "mock data" '
          'is the defect Phase 4 removed.\nFound in:\n${offenders.join('\n')}',
    );
  });
}

/// The products half of the catalogue, with a switch for the transport failure
/// the live app shows when the server is unreachable — so a refresh can fail
/// AFTER a good load and the page's stale-rows path is exercised.
class _FlakyProductsRepository extends FakeProductsRepository {
  bool fail = false;

  void setProducts(List<Product> products) =>
      setSnapshot(products: products, batches: const []);

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    if (fail) {
      throw const ProductsServiceException(
        'Cannot connect to the BuildPro server.',
      );
    }
    return super.loadCatalogue();
  }
}
