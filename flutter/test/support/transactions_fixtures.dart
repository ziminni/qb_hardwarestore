// Card S1: the three Transactions screens (cashier history, store manager
// transactions, stock manager sales) read the SAME viewmodel, so their tests and
// their goldens share one dataset. Kept here instead of copied three times so a
// change to the fixture cannot make one role's PNG disagree with another's.

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Answers `fetchTransactions` from memory; nothing here touches a server.
class StubSalesService extends SalesService {
  StubSalesService({this.rows = const [], this.error});

  final List<TransactionRecord> rows;

  /// When set, the load fails with this message instead of returning [rows].
  final String? error;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async {
    final failure = error;
    if (failure != null) throw SalesServiceException(failure);
    return rows;
  }
}

/// Four recorded sales covering what the screens must survive: a plain walk-in,
/// a requisition with a SEVEN DIGIT total and a long customer name, a refund and
/// a void. Timestamps are distinct so the date-and-time column has something to
/// tell apart.
List<TransactionRecord> transactionsFixture() => [
  _sale(
    id: 1,
    no: 'TRX-20261030-0001',
    at: DateTime(2026, 10, 30, 14, 14),
    customer: 'Dela Cruz Construction',
    source: 'WALK_IN',
    status: 'COMPLETED',
    items: [_line('BAG', 4, 250)],
    payments: const [TransactionPayment(method: 'CASH', amountTendered: 1000)],
  ),
  _sale(
    id: 2,
    no: 'TRX-20261030-0002',
    at: DateTime(2026, 10, 30, 9, 5),
    customer: 'Northern Mindanao Builders and Hardware Trading Corporation',
    source: 'REQUISITION',
    status: 'COMPLETED',
    items: [_line('CEM-40KG', 1200, 950)],
    payments: const [
      TransactionPayment(method: 'BANK_TRANSFER', amountTendered: 1140000),
    ],
  ),
  _sale(
    id: 3,
    no: 'TRX-20261029-0007',
    at: DateTime(2026, 10, 29, 16, 40),
    customer: 'Walk-in customer',
    source: 'WALK_IN',
    status: 'REFUNDED',
    items: [_line('PIPE-2IN', 2, 240)],
    payments: const [TransactionPayment(method: 'GCASH', amountTendered: 480)],
  ),
  _sale(
    id: 4,
    no: 'TRX-20261029-0006',
    at: DateTime(2026, 10, 29, 11, 20),
    customer: 'Reyes Trading',
    source: 'WALK_IN',
    status: 'VOID',
    items: [_line('TILE-60', 1, 320)],
  ),
];

/// The three pages under test, wrapped in the providers their shells read.
///
/// The real theme is used on purpose: a golden rendered with the default test
/// theme would not show what the app renders.
Widget transactionsApp({
  required Widget child,
  required InventorySalesViewmodel viewmodel,
  ThemeData? theme,
}) {
  return ChangeNotifierProvider<AuthViewmodel>.value(
    value: AuthViewmodel(AuthRepository(AuthService())),
    child: ChangeNotifierProvider<InventorySalesViewmodel>.value(
      value: viewmodel,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? AppTheme.lightTheme,
        home: child,
      ),
    ),
  );
}

TransactionLineItem _line(String code, double qty, double unitPrice) =>
    TransactionLineItem(
      variantUomId: 42,
      variantUomCode: code,
      qty: qty,
      unitPrice: unitPrice,
      subtotal: qty * unitPrice,
    );

TransactionRecord _sale({
  required int id,
  required String no,
  required DateTime at,
  required String customer,
  required String source,
  required String status,
  required List<TransactionLineItem> items,
  List<TransactionPayment> payments = const [],
}) => TransactionRecord(
  id: id,
  transactionNo: no,
  transDate: at,
  customerId: 3,
  customerName: customer,
  cashierName: 'Ana Reyes',
  source: source,
  originalTransactionId: null,
  status: status,
  grandTotal: items.fold<double>(0, (sum, line) => sum + line.subtotal),
  items: items,
  payments: payments,
);
