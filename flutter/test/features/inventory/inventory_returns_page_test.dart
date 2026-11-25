import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/payables_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_returns_page.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubPayablesService extends PayablesService {
  _StubPayablesService({
    required this.returns,
    this.error,
  });

  final List<SupplierReturn> returns;
  final String? error;

  @override
  Future<List<SupplierReturn>> fetchReturns({int? supplierId}) async {
    if (error != null) throw PayablesServiceException(error!);
    return returns;
  }
}

class _StubInventoryService extends InventoryService {
  @override
  Future<List<GoodsReceiptRecord>> fetchGoodsReceipts({
    int? purchaseOrderId,
  }) async => const [];
}

List<SupplierReturn> _fixtureReturns() => [
  SupplierReturn(
    id: 101,
    receiptId: 50,
    supplierId: 10,
    supplierName: 'Holcim Distributors',
    purchaseOrderId: 12,
    billId: 201,
    reason: 'Goods shrinkage / damaged bags during transit',
    createdByName: 'Stocker One',
    createdAt: DateTime(2026, 11, 25, 9, 15),
    creditNoteNumber: 'CN-20261125-0001',
    creditNoteTotal: 1850.0,
    creditNoteRemaining: 1850.0,
    lines: const [
      SupplierReturnLine(
        id: 1,
        receiptLineId: 900,
        qty: 5,
        baseQty: 5,
        creditValue: 1850,
        deductions: [],
        productName: 'Portland Cement',
        variantName: '40kg Bag',
        unitCode: 'BAG',
      ),
    ],
  ),
  SupplierReturn(
    id: 102,
    receiptId: 51,
    supplierId: 11,
    supplierName: 'Boysen Paints Supply',
    purchaseOrderId: 13,
    billId: 202,
    reason: 'Defective item — dented gallon tins',
    createdByName: 'Stocker One',
    createdAt: DateTime(2026, 11, 24, 14, 40),
    creditNoteNumber: 'CN-20261124-0002',
    creditNoteTotal: 1200.0,
    creditNoteRemaining: 0.0,
    lines: const [
      SupplierReturnLine(
        id: 2,
        receiptLineId: 901,
        qty: 2,
        baseQty: 2,
        creditValue: 1200,
        deductions: [],
        productName: 'Latex Paint',
        variantName: 'White 4L',
        unitCode: 'GAL',
      ),
    ],
  ),
];

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    List<SupplierReturn>? returns,
    String? error,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = AuthViewmodel(AuthRepository(AuthService()))
      ..user = const User(
        id: 2,
        username: 'stocker',
        email: 'stocker@qb.ph',
        fullName: 'Stocker One',
        role: Role(id: 3, name: 'inventory', displayName: 'Stock Manager'),
      );
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: InventoryReturnsPage(
            payablesService: _StubPayablesService(
              returns: returns ?? _fixtureReturns(),
              error: error,
            ),
            inventoryService: _StubInventoryService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists supplier returns with KPIs and New supplier return CTA', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(DataPanel<SupplierReturn>), findsOneWidget);
    expect(find.text('CN-20261125-0001'), findsOneWidget);
    expect(find.text('Holcim Distributors'), findsOneWidget);
    expect(find.text('CN-20261124-0002'), findsOneWidget);
    expect(find.text('Boysen Paints Supply'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('new-supplier-return-button')),
      findsOneWidget,
    );
  });

  testWidgets('credit filter chip narrows supplier returns list', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('Open credit'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CN-20261125-0001'), findsOneWidget);
    expect(find.text('CN-20261124-0002'), findsNothing);
  });

  testWidgets('search narrows supplier returns by reason or supplier', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'shrinkage');
    await tester.pumpAndSettle();

    expect(find.text('CN-20261125-0001'), findsOneWidget);
    expect(find.text('CN-20261124-0002'), findsNothing);
  });

  testWidgets('tapping a row opens supplier return details with returned lines', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('SR-101')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Portland Cement'), findsWidgets);
    expect(find.textContaining('Goods shrinkage'), findsWidgets);
    expect(find.textContaining('₱1,850.00'), findsWidgets);
  });

  testWidgets('shows error banner when loading supplier returns fails', (
    tester,
  ) async {
    await pump(
      tester,
      returns: const [],
      error: 'Cannot connect to the BuildPro server.',
    );

    expect(find.textContaining('Cannot connect'), findsOneWidget);
  });
}
