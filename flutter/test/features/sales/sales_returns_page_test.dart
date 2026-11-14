// Card M5: the Store Manager's Returns and refunds screen.
//
// The manager reads this list to answer "what came back, against which sale, and
// did it hold", and posts one correction of his own: a return with no original
// sale, which the cashier's till cannot (and must not) offer. So the list leads
// with the document number and its status, keeps the reason for the details
// sheet, and carries the unlinked correction as the one filled action on the
// page, behind a role check by CODE.

import 'package:client/data/models/role.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/views/sales_returns_page.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(
  Widget child,
  InventorySalesViewmodel viewmodel, {
  String? roleCode,
  String? roleLabel,
}) {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  if (roleCode != null) {
    auth.user = User(
      id: 1,
      username: 'u',
      email: 'u@demo.ph',
      fullName: 'U',
      role: Role(id: 1, name: roleCode, displayName: roleLabel ?? roleCode),
    );
  }
  return ChangeNotifierProvider<AuthViewmodel>.value(
    value: auth,
    child: ChangeNotifierProvider<InventorySalesViewmodel>.value(
      value: viewmodel,
      child: MaterialApp(home: child),
    ),
  );
}

class _StubSalesService extends SalesService {
  _StubSalesService() : super();

  List<TransactionRecord> rows = const [];
  String? error;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async {
    final failure = error;
    if (failure != null) throw SalesServiceException(failure);
    return rows;
  }

  @override
  Future<List<QuotationRecord>> fetchQuotations() => throw UnimplementedError();

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() => throw UnimplementedError();
}

TransactionRecord _row({
  required int id,
  required String no,
  required String source,
  int? original,
  String status = 'COMPLETED',
  double total = 100,
  List<TransactionLineItem> items = const [],
}) => TransactionRecord(
  id: id,
  transactionNo: no,
  transDate: DateTime(2026, 10, 19, 8),
  customerId: 3,
  customerName: 'Dela Cruz Construction',
  cashierName: 'Cashy Ir',
  source: source,
  originalTransactionId: original,
  status: status,
  grandTotal: total,
  items: items,
  payments: const [TransactionPayment(method: 'CASH', amountTendered: 100)],
);

const _twoLines = [
  TransactionLineItem(
    variantUomId: 1,
    variantUomCode: 'BAG',
    qty: 2,
    unitPrice: 50,
    subtotal: 100,
  ),
  TransactionLineItem(
    variantUomId: 2,
    variantUomCode: 'TILE',
    qty: 1,
    unitPrice: 30,
    subtotal: 30,
  ),
];

/// Three posted returns: a linked one with two lines, an UNLINKED one (the
/// manager's own kind, worth seven digits), and a voided one. The walk-in sale
/// is here to prove it never reaches the returns list.
List<TransactionRecord> _returns() => [
  _row(id: 9, no: 'TRX-20261019-0001', source: 'WALK_IN'),
  _row(
    id: 10,
    no: 'TRX-20261026-0001',
    source: 'RETURN',
    original: 9,
    total: -130,
    items: _twoLines,
  ),
  _row(
    id: 11,
    no: 'TRX-20261026-0002',
    source: 'RETURN',
    total: -1140000,
    items: const [
      TransactionLineItem(
        variantUomId: 3,
        variantUomCode: 'CEM-40KG',
        qty: 1200,
        unitPrice: 950,
        subtotal: 1140000,
      ),
    ],
  ),
  _row(
    id: 12,
    no: 'TRX-20261025-0009',
    source: 'RETURN',
    original: 8,
    status: 'VOID',
    total: -240,
    items: const [
      TransactionLineItem(
        variantUomId: 4,
        variantUomCode: 'PIPE-2IN',
        qty: 1,
        unitPrice: 240,
        subtotal: 240,
      ),
    ],
  ),
];

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    List<TransactionRecord>? rows,
    String? error,
    String? roleCode,
    String? roleLabel,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _StubSalesService()
      ..rows = rows ?? _returns()
      ..error = error;
    await tester.pumpWidget(
      _app(
        SalesReturnsPage(),
        InventorySalesViewmodel(service: service),
        roleCode: roleCode,
        roleLabel: roleLabel,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpAsManager(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    List<TransactionRecord>? rows,
    String? error,
  }) => pump(
    tester,
    size: size,
    rows: rows,
    error: error,
    roleCode: 'sales',
    roleLabel: 'Store Manager',
  );

  testWidgets('returns page lists RETURN rows with the reversed receipt', (
    tester,
  ) async {
    await pumpAsManager(tester);

    expect(find.text('TRX-20261026-0001'), findsOneWidget);
    // The original sale's number appears exactly once, as the linked receipt,
    // not as its own row.
    expect(find.text('TRX-20261019-0001'), findsOneWidget);
    expect(find.text('No customer returns available.'), findsNothing);
  });

  testWidgets('the list leads with the document and its status badge', (
    tester,
  ) async {
    await pumpAsManager(tester);

    final panel = find.byType(DataPanel<InventoryReturn>);
    expect(panel, findsOneWidget);
    expect(find.byKey(const ValueKey('DataPanel.table')), findsOneWidget);
    for (final label in ['Return', 'Date and time', 'Original sale', 'Items']) {
      expect(find.text(label), findsOneWidget, reason: 'column $label');
    }
    // The badge rides under the document number, so the reader sees what
    // happened to the return without a column of its own. Scoped to the panel:
    // the status chips carry the same words.
    expect(
      find.descendant(of: panel, matching: find.text('Completed')),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: panel, matching: find.text('Rejected')),
      findsOneWidget,
    );
  });

  testWidgets('the reason is not a table column: it lives on the document', (
    tester,
  ) async {
    await pumpAsManager(tester);

    expect(
      find.text('Reason'),
      findsNothing,
      reason: 'a free-text reason stretched the table to eight columns',
    );

    await tester.tap(find.byKey(const ValueKey('TRX-20261026-0001')));
    await tester.pumpAndSettle();

    final sheet = find.byType(SalesDocumentSheet);
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(of: sheet, matching: find.text('Reason')),
      findsOneWidget,
      reason: 'the reason is still readable, one tap away',
    );
    // Every line of a multi-line return, not a collapsed total.
    expect(
      find.descendant(of: sheet, matching: find.text('2 × ₱50.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('1 × ₱30.00')),
      findsOneWidget,
    );
  });

  testWidgets('a return with no original sale says so in words, not a dash', (
    tester,
  ) async {
    await pumpAsManager(tester);

    expect(find.text('Not linked'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('no sideways scroll track at 1440: the table fits its panel', (
    tester,
  ) async {
    await pumpAsManager(tester);

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
      reason:
          'QA saw a horizontal track here; a sideways table hides columns '
          'behind a scrollbar instead of fitting them',
    );
  });

  testWidgets('a status chip narrows the list to that status', (tester) async {
    await pumpAsManager(tester);

    expect(find.byType(FilterBar), findsOneWidget);
    await tester.tap(
      // Scoped to the bar: the chip label equals a row's status badge.
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('Rejected'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TRX-20261025-0009'), findsOneWidget);
    expect(find.text('TRX-20261026-0001'), findsNothing);
    expect(find.text('TRX-20261026-0002'), findsNothing);
  });

  testWidgets('a search that hides every return does not claim the store has '
      'none', (tester) async {
    await pumpAsManager(tester);

    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pumpAndSettle();

    expect(find.text('No returns match these filters.'), findsOneWidget);
    expect(find.text('No customer returns available.'), findsNothing);
  });

  testWidgets('an empty returns list states it plainly', (tester) async {
    await pumpAsManager(
      tester,
      rows: [_row(id: 9, no: 'TRX-20261019-0001', source: 'WALK_IN')],
    );

    expect(find.text('No customer returns available.'), findsOneWidget);
  });

  testWidgets('a narrow window shows each return as a card', (tester) async {
    await pumpAsManager(tester, size: const Size(760, 1200));

    expect(find.byKey(const ValueKey('DataPanel.cards')), findsOneWidget);
    expect(find.byKey(const ValueKey('DataPanel.table')), findsNothing);
  });

  testWidgets('a failed refresh keeps the rows it already had and names the '
      'failure', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _StubSalesService()..rows = _returns();
    final viewmodel = InventorySalesViewmodel(service: service);
    await tester.pumpWidget(
      _app(SalesReturnsPage(), viewmodel, roleCode: 'sales'),
    );
    await tester.pumpAndSettle();

    service.error = 'Cannot connect to the BuildPro server.';
    await viewmodel.load();
    await tester.pumpAndSettle();

    expect(find.text('TRX-20261026-0001'), findsOneWidget);
    expect(find.textContaining('Cannot connect'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  // Phase 5 Task 3: the unlinked correction lives on this page for the Store
  // Manager (and Admin) only — a cashier's POST would 403 server-side with
  // UNLINKED_RETURN_FORBIDDEN, so the button is not offered. Compared by role
  // CODE, never label.
  testWidgets('the store manager gets one filled action with its note', (
    tester,
  ) async {
    await pumpAsManager(tester);

    expect(
      find.widgetWithText(FilledButton, 'Unlinked return'),
      findsOneWidget,
    );
    expect(find.text('Manager only: no original sale'), findsOneWidget);
  });

  testWidgets('the admin may post an unlinked return too', (tester) async {
    await pump(tester, roleCode: 'admin', roleLabel: 'Administrator');

    expect(
      find.widgetWithText(FilledButton, 'Unlinked return'),
      findsOneWidget,
    );
  });

  testWidgets('a cashier is not offered the unlinked return', (tester) async {
    await pump(tester, roleCode: 'pos', roleLabel: 'Cashier');

    expect(find.text('Unlinked return'), findsNothing);
    expect(find.text('Manager only: no original sale'), findsNothing);
  });
}
