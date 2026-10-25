import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/dashboard/views/inventory_dashboard.dart';
import 'package:client/features/dashboard/widget/inventory_list_item.dart';
import 'package:client/features/dashboard/widget/inventory_section.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import '../../support/phase4_fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Product _product() => const Product(
  id: 1,
  categoryId: 1,
  categoryName: 'Cement',
  brandId: 1,
  brandName: 'QB',
  baseName: 'Portland Cement',
  description: '',
  imageUrl: '',
  isActive: true,
  variants: [
    ProductVariant(
      id: 1,
      productId: 1,
      baseUomId: 1,
      minStockThreshold: 50,
      maxStockLevel: 0,
      variantName: '40kg',
      baseUomCode: 'Bag',
      isActive: true,
    ),
  ],
);

InventoryBatch _batch() => InventoryBatch(
  id: 1,
  variantId: 1,
  receiptId: 1,
  initialQty: 100,
  currentQty: 95,
  unitCostLanded: 200,
  markupPercentage: 0,
  batchSellingPrice: 260,
  expirationDate: null,
  createdAt: DateTime(2026, 10, 19),
);

class _StubProductsRepository extends ProductsRepository {
  _StubProductsRepository(this.snapshot, {this.failure})
    : super(ProductsService());

  final ProductsSnapshot snapshot;
  final String? failure;

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    final failure = this.failure;
    if (failure != null) throw ProductsServiceException(failure);
    return snapshot;
  }
}

class _StubInventoryRepository extends InventoryRepository {
  _StubInventoryRepository({this.adjustments = const []})
    : failure = null,
      super(InventoryService());

  final List<StockAdjustment> adjustments;
  final String? failure;

  @override
  Future<List<SystemAlert>> loadAlerts() async => const [];

  @override
  Future<List<StockAdjustment>> loadAdjustments() async {
    final failure = this.failure;
    if (failure != null) throw InventoryServiceException(failure);
    return adjustments;
  }
}

ProductVariant _variant({
  required int id,
  required String name,
  required double threshold,
}) => ProductVariant(
  id: id,
  productId: 100 + id,
  baseUomId: 1,
  minStockThreshold: threshold,
  maxStockLevel: 0,
  variantName: name,
  baseUomCode: 'PC',
  isActive: true,
);

Product _stockProduct({required int id, required String name}) => Product(
  id: 100 + id,
  categoryId: 1,
  categoryName: 'Cat',
  brandId: 1,
  brandName: 'QB',
  baseName: name,
  description: '',
  imageUrl: '',
  isActive: true,
  variants: [
    _variant(
      id: id,
      name: 'v$id',
      threshold: const {
        1: 50,
        2: 50,
        3: 20,
        4: 50,
        5: 50,
        6: 50,
        7: 20,
      }[id]!.toDouble(),
    ),
  ],
);

InventoryBatch _stockBatch({required int id, required double qty}) =>
    InventoryBatch(
      id: id,
      variantId: id,
      receiptId: 1,
      initialQty: 100,
      currentQty: qty,
      unitCostLanded: 200,
      markupPercentage: 0,
      batchSellingPrice: 260,
      expirationDate: null,
      createdAt: DateTime(2026, 10, 19),
    );

Future<void> _pump(WidgetTester tester, InventoryViewmodel inventory) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: ChangeNotifierProvider<InventoryViewmodel>.value(
        value: inventory,
        child: const MaterialApp(home: InventoryDashboard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a failed load shows the error with a retry', (tester) async {
    final inventory = InventoryViewmodel(
      products: _StubProductsRepository(
        const ProductsSnapshot(products: [], batches: []),
        failure: 'Cannot connect to the BuildPro server.',
      ),
      inventory: _StubInventoryRepository(),
      catalogue: FakeCatalogueRepository(),
    );
    await _pump(tester, inventory);

    expect(find.textContaining('Cannot connect'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('an empty catalogue states it plainly, never mock numbers', (
    tester,
  ) async {
    final inventory = InventoryViewmodel(
      products: _StubProductsRepository(
        const ProductsSnapshot(products: [], batches: []),
      ),
      inventory: _StubInventoryRepository(),
      catalogue: FakeCatalogueRepository(),
    );
    await _pump(tester, inventory);

    expect(find.text('1,248'), findsNothing);
    expect(find.textContaining('No products'), findsOneWidget);
  });

  testWidgets('restock queue leads with out-of-stock and signals overflow', (
    tester,
  ) async {
    // Catalogue order is deliberately non-urgent: in-stock, then lows, then
    // out-of-stock. The queue must re-rank: out first, lows by coverage, and
    // say so when it cuts the list.
    final products = [
      _stockProduct(id: 1, name: 'In Stock Item'),
      _stockProduct(id: 2, name: 'Low B'),
      _stockProduct(id: 3, name: 'Out C'),
      _stockProduct(id: 4, name: 'Low D'),
      _stockProduct(id: 5, name: 'Low E'),
      _stockProduct(id: 6, name: 'Low F'),
      _stockProduct(id: 7, name: 'Out G'),
    ];
    final quantities = {
      1: 95.0,
      2: 10.0,
      3: 0.0,
      4: 25.0,
      5: 40.0,
      6: 5.0,
      7: 0.0,
    };
    final inventory = InventoryViewmodel(
      products: _StubProductsRepository(
        ProductsSnapshot(
          products: products,
          batches: [
            for (final id in quantities.keys)
              _stockBatch(id: id, qty: quantities[id]!),
          ],
        ),
      ),
      inventory: _StubInventoryRepository(),
      catalogue: FakeCatalogueRepository(),
    );
    await _pump(tester, inventory);

    // Out-of-stock leads, lows follow by coverage (F 0.1, B 0.2, D 0.5):
    // C, G, F, B, D shown; E (0.8) cut with an overflow signal. Scoped to
    // the queue subtree — the table lists every variant, so bare text
    // finders cannot tell the two apart.
    final queue = find.descendant(
      of: find.widgetWithText(InventorySection, 'Restock queue'),
      matching: find.byType(InventoryListItem),
    );
    final titles = tester
        .widgetList<InventoryListItem>(queue)
        .map((item) => item.title)
        .toList();
    expect(titles, [
      'Out C v3',
      'Out G v7',
      'Low F v6',
      'Low B v2',
      'Low D v4',
      startsWith('+1 more'),
    ]);
    expect(find.textContaining('+1 more'), findsOneWidget);
  });

  testWidgets('live rows render product, stock and movement data', (
    tester,
  ) async {
    final inventory = InventoryViewmodel(
      products: _StubProductsRepository(
        ProductsSnapshot(products: [_product()], batches: [_batch()]),
      ),
      catalogue: FakeCatalogueRepository(),
      inventory: _StubInventoryRepository(
        adjustments: [
          StockAdjustment(
            id: 3,
            variantId: 1,
            userId: 2,
            adjustmentType: StockAdjustmentType.shrinkage,
            quantityAdjusted: -2,
            remarks: 'torn bag',
            timestamp: DateTime(2026, 10, 19, 10),
          ),
        ],
      ),
    );
    await _pump(tester, inventory);

    expect(find.textContaining('Portland Cement'), findsWidgets);
    expect(find.textContaining('torn bag'), findsOneWidget);
    expect(find.text('1,248'), findsNothing);
  });
}
