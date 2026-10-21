import 'dart:typed_data';

import 'package:client/app.dart';
import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/dashboard/views/admin_dashboard.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/dashboard/viewmodels/admin_overview_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:dio/dio.dart';
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

SalesSummary _summary() => const SalesSummary(
  from: '2026-10-19',
  to: '2026-10-19',
  totalTransactions: 7,
  totalGross: 11716,
  totalVat: 0,
  totalDiscounts: 0,
  days: [],
);

TransactionRecord _sale() => TransactionRecord(
  id: 9,
  transactionNo: 'TRX-20261019-0001',
  transDate: DateTime(2026, 10, 19, 8),
  customerId: 3,
  customerName: 'Dela Cruz Construction',
  cashierName: 'Cashy Ir',
  source: 'WALK_IN',
  originalTransactionId: null,
  status: 'COMPLETED',
  grandTotal: 100,
  items: const [
    TransactionLineItem(
      variantUomId: 1,
      variantUomCode: 'BAG',
      qty: 2,
      unitPrice: 50,
      subtotal: 100,
    ),
  ],
  payments: const [TransactionPayment(method: 'CASH', amountTendered: 100)],
);

class _StubProductsRepository extends ProductsRepository {
  _StubProductsRepository() : super(ProductsService());

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      ProductsSnapshot(products: [_product()], batches: [_batch()]);
}

class _StubInventoryRepository extends InventoryRepository {
  _StubInventoryRepository() : super(InventoryService());

  @override
  Future<List<SystemAlert>> loadAlerts() async => const [];

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => const [];
}

class _StubReportsService extends ReportsService {
  _StubReportsService({this.failure}) : super();

  final String? failure;

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    final failure = this.failure;
    if (failure != null) throw ReportsServiceException(failure);
    return _summary();
  }
}

class _StubSalesService extends SalesService {
  _StubSalesService() : super();

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async => [
    _sale(),
  ];

  @override
  Future<List<QuotationRecord>> fetchQuotations() => throw UnimplementedError();

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() => throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, {String? reportsFailure}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryViewmodel>.value(
            value: InventoryViewmodel(
              products: _StubProductsRepository(),
              inventory: _StubInventoryRepository(),
            ),
          ),
          ChangeNotifierProvider<AdminOverviewViewmodel>.value(
            value: AdminOverviewViewmodel(
              reports: _StubReportsService(failure: reportsFailure),
              sales: _StubSalesService(),
            ),
          ),
        ],
        child: const MaterialApp(home: AdminDashboard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FailingInventoryRepository extends InventoryRepository {
  _FailingInventoryRepository() : super(InventoryService());

  @override
  Future<List<SystemAlert>> loadAlerts() async =>
      throw const InventoryServiceException('Cannot connect.');

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => const [];
}

Future<void> _pumpInventoryFailing(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryViewmodel>.value(
            value: InventoryViewmodel(
              products: _StubProductsRepository(),
              inventory: _FailingInventoryRepository(),
            ),
          ),
          ChangeNotifierProvider<AdminOverviewViewmodel>.value(
            value: AdminOverviewViewmodel(
              reports: _StubReportsService(),
              sales: _StubSalesService(),
            ),
          ),
        ],
        child: const MaterialApp(home: AdminDashboard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Answers every request the way an unreachable backend does. The route-level
/// test renders the REAL `AdminOverviewViewmodel`, and its load must fail into
/// the screen's error path rather than hang the fake clock.
class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: 'offline',
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  // The defect this pins: `routes.dart` built `const AdminDashboard()` with no
  // provider above it, and `main.dart` never registered
  // `AdminOverviewViewmodel`, so opening /admin/dashboard threw a
  // ProviderException before a single metric could render. Every test above
  // injects the viewmodel by hand, which is exactly why none of them caught it.
  testWidgets('the admin dashboard route provides its own overview viewmodel', (
    tester,
  ) async {
    ApiClient.instance.init();
    ApiClient.instance.dio.httpClientAdapter = _OfflineAdapter();

    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = AuthViewmodel(AuthRepository(AuthService()))
      ..user = const User(
        id: 1,
        username: 'admin',
        email: 'admin@example.com',
        fullName: 'Admin User',
        role: Role(id: 1, name: 'admin', displayName: 'Admin'),
        isActive: true,
      );

    // Only the APP-ROOT providers are supplied here, and deliberately NOT
    // `AdminOverviewViewmodel`: the route itself must own that one. A global
    // registration would make this test pass while leaving the route broken.
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: auth,
        child: ChangeNotifierProvider<InventoryViewmodel>.value(
          value: InventoryViewmodel(
            products: _StubProductsRepository(),
            inventory: _StubInventoryRepository(),
          ),
          child: MyApp(auth: auth),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AdminDashboard), findsOneWidget);
  });

  testWidgets('a failed inventory load never renders zero-as-data metrics', (
    tester,
  ) async {
    await _pumpInventoryFailing(tester);

    expect(find.textContaining('Stock data could not be loaded'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('a failed load shows the error with a retry', (tester) async {
    await _pump(
      tester,
      reportsFailure: 'Cannot connect to the BuildPro server.',
    );

    expect(find.textContaining('Cannot connect'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('live overview renders server data, never mock fixtures', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('11716'), findsWidgets);
    expect(find.textContaining('TRX-20261019-0001'), findsOneWidget);
    expect(find.text('84,250'), findsNothing);
    expect(find.textContaining('Maria Santos signed in'), findsNothing);
  });
}
