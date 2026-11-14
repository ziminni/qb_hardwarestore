// Phase 1d Task 11 (decision 17): the categories screen says how many
// categories there are three ways: how many exist, how many are offered and how
// many are archived. The tiles are a fact about the LOADED catalogue, so a
// failed read shows the failure and no tiles rather than three zeros.
//
// The card's own bar is the other half: gold while a category is offered, muted
// once it is archived, and the badge spells the same thing in words (a bar alone
// would be colour-only).

import 'package:client/core/constants/app_colors.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/categories/views/categories_page.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// The bar a card carries at its leading edge: gold while active, muted when
/// archived.
const activeBar = ValueKey('CategoryCard.bar.active');
const archivedBar = ValueKey('CategoryCard.bar.archived');

void main() {
  InventoryViewmodel store({
    required List<Product> products,
    List<dynamic> categories = const [],
  }) {
    return InventoryViewmodel(
      products: FakeProductsRepository(products: products),
      inventory: FakeInventoryRepository(),
      catalogue: FakeCatalogueRepository(
        categories: [
          category(id: 1, name: 'Cement'),
          category(id: 2, name: 'Plumbing', isActive: false),
          category(id: 3, name: 'Paint'),
        ],
      ),
    );
  }

  Future<void> pump(WidgetTester tester, InventoryViewmodel inventory) async {
    await inventory.load();
    tester.view.physicalSize = const Size(1600, 1400);
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

  String tileValue(WidgetTester tester, String label) {
    final tile = tester.widget<MetricTile>(
      find.ancestor(of: find.text(label), matching: find.byType(MetricTile)),
    );
    return tile.value;
  }

  testWidgets('the page counts all, active and archived categories', (
    tester,
  ) async {
    await pump(
      tester,
      store(
        products: [
          product(id: 1, name: 'Portland Cement', categoryId: 1),
          product(id: 2, name: 'PVC Pipe', categoryId: 2),
        ],
      ),
    );

    expect(find.byType(MetricTile), findsNWidgets(3));
    expect(tileValue(tester, 'Categories'), '3');
    expect(tileValue(tester, 'Active'), '2');
    expect(tileValue(tester, 'Archived'), '1');
  });

  // A failed read established nothing, so three tiles reading zero would be a
  // claim the screen cannot make.
  testWidgets('a failed load shows the failure and no tiles', (tester) async {
    final inventory = InventoryViewmodel(
      products: _FailingProductsRepository(),
      inventory: FakeInventoryRepository(),
      catalogue: FakeCatalogueRepository(),
    );

    await pump(tester, inventory);

    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);
    expect(find.byType(MetricTile), findsNothing);
  });

  testWidgets('an active card carries the gold bar and an archived one the '
      'muted bar', (tester) async {
    await pump(tester, store(products: const []));

    final gold = tester.widget<Container>(find.byKey(activeBar).first);
    expect(
      (gold.decoration! as BoxDecoration).color,
      AppColors.brandGold,
      reason: 'gold marks the categories still offered',
    );

    final muted = tester.widget<Container>(find.byKey(archivedBar));
    expect(
      (muted.decoration! as BoxDecoration).color,
      AppColors.disabled,
      reason: 'an archived category reads quieter, and its badge says so',
    );

    // Words, not colour alone.
    expect(find.text('Archived'), findsWidgets);
  });
}

class _FailingProductsRepository extends FakeProductsRepository {
  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      throw const ProductsServiceException(
        'Cannot connect to the BuildPro server.',
      );
}
