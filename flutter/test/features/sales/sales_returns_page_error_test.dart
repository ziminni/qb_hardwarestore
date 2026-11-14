// Card M5: what a failure looks like on the Store Manager's Returns screen.
//
// Two different facts, two different pictures: a FIRST load that failed is one
// failure with a retry and no "no returns" underneath it (the failed read never
// established that), while a REFRESH that failed keeps the rows it already had
// and names the failure above them.

import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/views/sales_returns_page.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(Widget child, InventorySalesViewmodel viewmodel) =>
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: ChangeNotifierProvider<InventorySalesViewmodel>.value(
        value: viewmodel,
        child: MaterialApp(home: child),
      ),
    );

class _FailingSalesService extends SalesService {
  _FailingSalesService() : super();

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async =>
      throw const SalesServiceException(
        'Cannot connect to the BuildPro server.',
      );

  @override
  Future<List<QuotationRecord>> fetchQuotations() => throw UnimplementedError();

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() => throw UnimplementedError();
}

void main() {
  testWidgets('a failed load shows one failure with a retry, not an empty '
      'list under it', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        const SalesReturnsPage(),
        InventorySalesViewmodel(service: _FailingSalesService()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot connect'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    expect(
      find.byType(EmptyState),
      findsNothing,
      reason: 'a failed read has not established that the store has no returns',
    );
    expect(find.text('No customer returns available.'), findsNothing);
  });
}
