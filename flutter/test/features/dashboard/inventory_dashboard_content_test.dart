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
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Product _product() => const Product(
  id: 1, categoryId: 1, categoryName: 'Cement', brandId: 1, brandName: 'QB',
  baseName: 'Portland Cement', description: '', imageUrl: '', isActive: true,
  variants: [
    ProductVariant(
      id: 1, productId: 1, baseUomId: 1, minStockThreshold: 50,
      maxStockLevel: 0, variantName: '40kg', baseUomCode: 'Bag',
      isActive: true,
    ),
  ],
);

InventoryBatch _batch() => InventoryBatch(
  id: 1, variantId: 1, receiptId: 1, initialQty: 100, currentQty: 95,
  unitCostLanded: 200, markupPercentage: 0, batchSellingPrice: 260,
  expirationDate: null, createdAt: DateTime(2026, 10, 19),
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
    : failure = null, super(InventoryService());

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
    );
    await _pump(tester, inventory);

    expect(find.text('1,248'), findsNothing);
    expect(find.textContaining('No products'), findsOneWidget);
  });

  testWidgets('live rows render product, stock and movement data', (
    tester,
  ) async {
    final inventory = InventoryViewmodel(
      products: _StubProductsRepository(
        ProductsSnapshot(products: [_product()], batches: [_batch()]),
      ),
      inventory: _StubInventoryRepository(
        adjustments: [
          StockAdjustment(
            id: 3, variantId: 1, userId: 2,
            adjustmentType: StockAdjustmentType.shrinkage,
            quantityAdjusted: -2, remarks: 'torn bag',
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
