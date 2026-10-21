// Stocker-workflow phases 1-3 render checks.
//
// Three screens had to behave differently on purpose:
//  - Returns reads the live RETURN transactions through `InventorySalesViewmodel`
//    (the `inventory` role has GET on /api/v1/transactions/ via IsPOSOrReadOnly);
//  - Reports makes NO API call, because every /api/v1/reports/* endpoint is
//    IsManagerRole-gated and a stocker would only ever get a 403 spinner;
//  - Settings is a static read-only form with NO Save button, because the
//    stocker cannot change store settings and the shared form's Save button is
//    a no-op even for admins.
//
// Each test asserts the absence that matters as well as the presence: a spinner
// on Reports or a "Save settings" button on Settings would mean the screen
// promises something the role cannot do.

import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_reports_page.dart';
import 'package:client/features/inventory/views/inventory_returns_page.dart';
import 'package:client/features/inventory/views/inventory_settings_page.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubSalesService extends SalesService {
  _StubSalesService({this.rows = const [], this.failure});

  final List<TransactionRecord> rows;
  final String? failure;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async {
    final failure = this.failure;
    if (failure != null) throw SalesServiceException(failure);
    return rows;
  }
}

TransactionRecord _returnRow() => TransactionRecord(
  id: 10,
  transactionNo: 'TRX-20261019-0002',
  transDate: DateTime(2026, 10, 19, 9),
  customerId: 3,
  customerName: 'Dela Cruz Construction',
  cashierName: 'Cashy Ir',
  source: 'RETURN',
  originalTransactionId: 9,
  status: 'COMPLETED',
  grandTotal: -50,
  items: const [
    TransactionLineItem(
      variantUomId: 1,
      variantUomCode: 'BAG',
      qty: -1,
      unitPrice: 50,
      subtotal: -50,
    ),
  ],
  payments: const [
    TransactionPayment(method: 'CASH', amountTendered: -50),
  ],
);

Future<void> _pump(WidgetTester tester, Widget page, {SalesService? sales}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewmodel>(
          create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        ),
        ChangeNotifierProvider<InventorySalesViewmodel>(
          create: (_) => InventorySalesViewmodel(service: sales ?? _StubSalesService()),
        ),
      ],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Returns', () {
    testWidgets('lists the live RETURN transactions', (tester) async {
      await _pump(
        tester,
        const InventoryReturnsPage(),
        sales: _StubSalesService(rows: [_returnRow()]),
      );

      expect(find.text('Returns & Refunds'), findsOneWidget);
      expect(find.text('TRX-20261019-0002'), findsOneWidget);
      expect(find.text('No returns recorded.'), findsNothing);
    });

    testWidgets('an empty result says so instead of showing a blank table', (
      tester,
    ) async {
      await _pump(tester, const InventoryReturnsPage());
      expect(find.text('No returns recorded.'), findsOneWidget);
    });

    testWidgets('a failed load shows the error with a retry', (tester) async {
      await _pump(
        tester,
        const InventoryReturnsPage(),
        sales: _StubSalesService(failure: 'Cannot connect to the BuildPro server.'),
      );

      expect(find.textContaining('Cannot connect'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    });
  });

  group('Reports', () {
    testWidgets('states manager access instead of calling a 403 endpoint', (
      tester,
    ) async {
      await _pump(tester, const InventoryReportsPage());

      expect(find.text('Reports'), findsWidgets);
      expect(
        find.text('Reports are available to Store Managers and above.'),
        findsOneWidget,
      );
      expect(find.text('Ask your manager for a summary.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('Settings', () {
    testWidgets('shows the store details read-only, with no Save button', (
      tester,
    ) async {
      await _pump(tester, const InventorySettingsPage());

      // Read the fields themselves: a disabled TextFormField renders its value
      // in more than one descendant, so a bare `find.text` cannot say whether
      // the value is editable or not.
      final fields = tester
          .widgetList<TextFormField>(find.byType(TextFormField))
          .toList();
      expect(
        fields.map((field) => field.initialValue).toList(),
        ['Queen Builders', 'admin@queenbuilders.local', '+63 900 000 0000'],
      );
      expect(fields.every((field) => field.enabled == false), isTrue);
      expect(find.text('Save settings'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
