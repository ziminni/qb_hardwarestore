import 'package:client/core/network/paged.dart';
import 'package:client/data/models/price_change.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/views/price_list_page.dart';
import 'package:client/features/products/widgets/products_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

class _StubPriceRepository extends FakeProductsRepository {
  _StubPriceRepository({
    required super.products,
    required super.batches,
    required this.changes,
  });

  final List<StorePriceChange> changes;
  String? lastQuery;
  String? lastSince;
  String? lastUntil;

  @override
  Future<Paged<StorePriceChange>> fetchPriceChanges({
    int? productId,
    String? since,
    String? until,
    String? query,
    int page = 1,
  }) async {
    lastQuery = query;
    lastSince = since;
    lastUntil = until;
    final q = (query ?? '').trim().toLowerCase();
    final filtered = changes.where((c) {
      if (q.isEmpty) return true;
      return c.productName.toLowerCase().contains(q) ||
          c.barcodeQr.toLowerCase().contains(q);
    }).toList();
    return Paged<StorePriceChange>(
      items: filtered,
      total: filtered.length,
      hasMore: false,
    );
  }
}

void main() {
  late _StubPriceRepository repository;
  late InventoryViewmodel inventory;
  late List<int> loadedHistoryUnitIds;

  final changedTime = DateTime.utc(2026, 11, 20, 9, 30);

  // Each selling unit gets its own timeline, so a merged product view has
  // something to interleave.
  Future<List<PriceHistoryEntry>> loadHistory(int unitId) async {
    loadedHistoryUnitIds.add(unitId);
    return unitId == 1002
        ? [
            PriceHistoryEntry(
              oldPrice: 90,
              newPrice: 100,
              changedAt: changedTime,
              actor: 'mgr',
              source: 'CATALOGUE',
            ),
          ]
        : [
            PriceHistoryEntry(
              oldPrice: 12,
              newPrice: 15,
              changedAt: changedTime.subtract(const Duration(days: 2)),
              actor: 'mgr',
              source: 'ADMIN',
            ),
          ];
  }

  setUp(() {
    final products = [
      product(
        id: 1,
        name: 'Latex Paint',
        categoryName: 'Paints',
        brandName: 'Boysen',
        variants: [
          variant(
            id: 101,
            productId: 1,
            name: 'White 1L',
            baseUomId: 1,
            baseUomCode: 'PC',
            sellingUoms: [
              VariantUom(
                id: 1001,
                variantId: 101,
                uomId: 1,
                uomCode: 'PC',
                uomName: 'Piece',
                barcodeQr: 'QB001001-1',
                conversionFactor: 1,
                defaultSellingPrice: 15,
                lastPriceChangedAt: changedTime,
              ),
              VariantUom(
                id: 1002,
                variantId: 101,
                uomId: 2,
                uomCode: 'BOX',
                uomName: 'Box',
                barcodeQr: 'QB001002-2',
                conversionFactor: 10,
                defaultSellingPrice: 100,
                lastPriceChangedAt: changedTime,
              ),
            ],
          ),
        ],
      ),
    ];
    // Cost per base PC = 8.00 -> cost per BOX (x10) = 80.00 -> margin = (100 - 80)/100 = 20.0%
    final batches = [batch(id: 1, variantId: 101, qty: 50, cost: 8)];
    final changes = [
      StorePriceChange(
        id: 1,
        variantUomId: 1002,
        productId: 1,
        productName: 'Latex Paint',
        variantName: 'White 1L',
        unitCode: 'BOX',
        barcodeQr: 'QB001002-2',
        oldPrice: 90,
        newPrice: 100,
        changeAmount: 10,
        changePercent: 11.11,
        changedAt: changedTime,
        changedByName: 'Ana Cruz',
        source: 'CATALOGUE',
      ),
    ];

    repository = _StubPriceRepository(
      products: products,
      batches: batches,
      changes: changes,
    );
    inventory = InventoryViewmodel.seeded(
      catalogue: repository,
      inventory: FakeInventoryRepository(),
      catalogueLists: FakeCatalogueRepository(),
      products: products,
      batches: batches,
      stockOnHand: onHandFromBatches(batches),
    );
    loadedHistoryUnitIds = <int>[];
  });

  Future<void> pumpPage(WidgetTester tester, {bool salesShell = false}) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final auth = AuthViewmodel(AuthRepository(AuthService()))
      ..user = User(
        id: 1,
        username: 'mgr',
        email: 'mgr@qb.ph',
        fullName: 'Ana Cruz',
        role: Role(
          id: 1,
          name: salesShell ? 'sales' : 'inventory',
          displayName: salesShell ? 'Store Manager' : 'Stock Manager',
        ),
      );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<AuthViewmodel>.value(value: auth),
        ],
        child: MaterialApp(
          home: salesShell
              ? SalesPriceListPage(
                  productsRepository: repository,
                  priceHistoryLoader: loadHistory,
                )
              : InventoryPriceListPage(
                  productsRepository: repository,
                  priceHistoryLoader: loadHistory,
                ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Price list shows price, cost per unit, margin %, and opens unit history on tap', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text('₱15.00'), findsOneWidget);
    expect(find.text('₱8.00'), findsOneWidget);
    expect(find.text('46.7%'), findsOneWidget);

    expect(find.text('₱100.00'), findsOneWidget);
    expect(find.text('₱80.00'), findsOneWidget);
    expect(find.text('20.0%'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('price-list-row-1002')));
    await tester.pumpAndSettle();

    expect(loadedHistoryUnitIds, contains(1002));
    expect(find.text('Price History'), findsOneWidget);
    expect(find.text('₱90.00 → ₱100.00'), findsOneWidget);
  });

  testWidgets(
    'A price list row opens ONE product timeline holding every selling unit',
    (tester) async {
      await pumpPage(tester);

      await tester.tap(find.byKey(const ValueKey('price-list-row-1002')));
      await tester.pumpAndSettle();

      // Both selling units of the product are on the timeline, not just the
      // tapped row's unit.
      expect(loadedHistoryUnitIds.toSet(), {1001, 1002});
      expect(find.text('₱90.00 → ₱100.00'), findsOneWidget);
      expect(find.text('₱12.00 → ₱15.00'), findsOneWidget);
      // Each row says which unit it belongs to and where the change came from.
      expect(find.textContaining('BOX (×10)'), findsOneWidget);
      // The product sells one variant, so the base unit reads as its code alone.
      expect(find.textContaining('PC · '), findsOneWidget);
      expect(find.textContaining('Catalogue'), findsOneWidget);
      expect(find.textContaining('Admin'), findsOneWidget);
    },
  );

  testWidgets('Recent price changes tab shows store-wide changes, filters by search, and opens history', (
    tester,
  ) async {
    await pumpPage(tester, salesShell: true);

    await tester.tap(find.byKey(const ValueKey('recent-price-changes-tab')));
    await tester.pumpAndSettle();

    expect(find.text('Latex Paint · White 1L (BOX)'), findsOneWidget);
    expect(find.text('₱90.00 → ₱100.00'), findsOneWidget);
    expect(find.text('+₱10.00 (+11.1%)'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('recent-changes-search')),
      'QB001002-2',
    );
    await tester.tap(find.byKey(const ValueKey('recent-changes-apply')));
    await tester.pumpAndSettle();
    expect(repository.lastQuery, 'QB001002-2');

    await tester.tap(find.byKey(const ValueKey('recent-change-row-1')));
    await tester.pumpAndSettle();
    expect(loadedHistoryUnitIds, [1002]);
    expect(find.text('Price History'), findsOneWidget);
  });
}
