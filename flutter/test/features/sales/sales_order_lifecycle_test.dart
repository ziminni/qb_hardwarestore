// Phase 7 F1 — the sales side of the order lifecycle (decision 19).
//
// What the sales screen must show now that a server owns the lifecycle:
//   * the status the RULES see (legacy PROCESSING/READY read as Confirmed, and
//     PARTIAL/CANCELLED are real statuses);
//   * per line what was ordered, fulfilled and still remains, and whether the
//     shop can cover the remainder today (a live hint — nothing is reserved);
//   * Edit and Cancel for a Store Manager/Admin ONLY, and neither for a
//     cashier or a Stock Manager;
//   * a server refusal lands INSIDE the dialog with the input intact, and an
//     above-cap edit asks a manager to approve in place, then resubmits once.
//
// Everything is pumped at 760 px (the narrow desktop the app must stay honest
// at), with the role supplied by a real AuthViewmodel, exactly as the live app
// decides it.

import 'package:client/data/models/customer.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/discount_approval_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/views/sales_orders_page.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/features/sales/widgets/sales_order_cancel_dialog.dart';
import 'package:client/features/sales/widgets/sales_order_form_dialog.dart';
import 'package:client/features/pos/widgets/pos_discount_approval_dialog.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// Answers from memory. The refusal fields exist because the dialog's whole job
/// is to show the server's sentence, not a generic one.
class _StubSalesService extends SalesService {
  _StubSalesService() : super();

  List<SalesOrderRow> orders = const [];

  /// Every edit the dialog submitted, in order — the token sits on the second.
  final List<SalesOrderEdit> edits = [];

  /// Every create the dialog submitted, in order — the token sits on the second.
  final List<SalesOrderDraft> creates = [];

  /// Every cancel reason the dialog submitted.
  final List<String> cancels = [];

  /// When set, an edit is refused with this sentence (and optional code).
  String? editRefusal;
  String? editRefusalCode;
  double? editRefusalPercent;

  /// Same for a create. [refuseEveryCreate] fails BOTH attempts, so the bounded
  /// retry is pinned: a second refusal must land inline, never loop.
  String? createRefusal;
  String? createRefusalCode;
  double? createRefusalPercent;
  bool refuseEveryCreate = false;

  /// Same for a cancel.
  String? cancelRefusal;

  @override
  Future<List<QuotationRecord>> fetchQuotations() async => const [];

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() async => orders;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async =>
      const [];

  @override
  Future<SalesOrderRow> createSalesOrder(SalesOrderDraft draft) async {
    creates.add(draft);
    final refusal = createRefusal;
    if (refusal != null) {
      // Refuse the FIRST attempt only unless every attempt is refused: the
      // approval retry is the flow being pinned.
      if (refuseEveryCreate ||
          createRefusalCode == null ||
          creates.length == 1) {
        throw SalesServiceException(
          refusal,
          code: createRefusalCode,
          requestedPercent: createRefusalPercent,
        );
      }
    }
    return orders.first;
  }

  @override
  Future<SalesOrderRow> editSalesOrder(int id, SalesOrderEdit edit) async {
    edits.add(edit);
    final refusal = editRefusal;
    if (refusal != null) {
      // Refuse the FIRST attempt only when a code is set, so the approval retry
      // can succeed: that is the whole flow being pinned.
      if (editRefusalCode == null || edits.length == 1) {
        throw SalesServiceException(
          refusal,
          code: editRefusalCode,
          requestedPercent: editRefusalPercent,
        );
      }
    }
    return orders.first;
  }

  @override
  Future<SalesOrderRow> cancelSalesOrder(
    int id, {
    required String reason,
  }) async {
    cancels.add(reason);
    final refusal = cancelRefusal;
    if (refusal != null) throw SalesServiceException(refusal);
    return orders.first;
  }
}

class _StubCustomerService extends CustomerService {
  _StubCustomerService() : super();

  @override
  Future<List<Customer>> fetchCustomers() async => const [
    Customer(id: 3, name: 'Dela Cruz Construction', customerType: 'REGULAR'),
  ];
}

/// Hands back a token without a server, so the approval branch is exercised.
class _StubApprovalService extends DiscountApprovalService {
  _StubApprovalService() : super();

  final List<double> asked = [];

  @override
  Future<DiscountApproval> request({
    required String username,
    required String password,
    required double percent,
    required String reason,
  }) async {
    asked.add(percent);
    return DiscountApproval(
      token: 'tok-1',
      percent: percent,
      approver: 'Manager',
    );
  }
}

/// The role CODE the server sends as `role.name`, keyed by the label a person
/// reads — the fixture trap Phase 4 already paid for.
const _roleCodes = {
  'Store Manager': 'sales',
  'System Administrator': 'admin',
  'Cashier': 'pos',
  'Stock Manager': 'inventory',
};

AuthViewmodel _auth({String? role}) {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  if (role != null) {
    auth.user = User(
      id: 1,
      username: 'manager',
      email: 'manager@qb.ph',
      fullName: 'Ana Lopez',
      role: Role(id: 4, name: _roleCodes[role]!, displayName: role),
    );
    auth.selectArea(_roleCodes[role]!);
  }
  return auth;
}

SalesOrderRow _order({
  int id = 7,
  String number = 'SO-20261019-0001',
  String status = 'CONFIRMED',
  String createdAt = '2026-10-19T08:00:00Z',
  List<OrderLineItem> items = const [
    OrderLineItem(variantUomId: 501, qty: 10, unitPrice: 250),
  ],
}) => SalesOrderRow(
  id: id,
  number: number,
  customerId: 3,
  quotationId: null,
  status: status,
  createdAt: createdAt,
  items: items,
);

Future<InventoryViewmodel> _inventory() async {
  final inventory = InventoryViewmodel(
    products: FakeProductsRepository(
      products: [
        product(
          id: 1,
          name: 'Cement Bag',
          categoryName: 'Hardware',
          brandName: 'BuildPro',
          variants: [
            variant(
              id: 5,
              productId: 1,
              name: '40kg',
              threshold: 1,
              maxStockLevel: 100,
              sellingUoms: [
                variantUom(id: 501, variantId: 5, price: 250, uomCode: 'BAG'),
              ],
            ),
          ],
        ),
      ],
      batches: [batch(id: 1, variantId: 5, qty: 100)],
    ),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  await inventory.load();
  return inventory;
}

void main() {
  late _StubSalesService sales;
  late _StubApprovalService approvals;

  setUp(() {
    sales = _StubSalesService();
    approvals = _StubApprovalService();
  });

  /// Pumps the orders page at 760 px with a live inventory and a REAL role.
  Future<void> pumpOrders(WidgetTester tester, {String? role}) async {
    tester.view.physicalSize = const Size(760, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final inventory = await _inventory();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>.value(value: _auth(role: role)),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<SalesModuleViewmodel>(
            create: (_) => SalesModuleViewmodel(
              service: sales,
              customerService: _StubCustomerService(),
            ),
          ),
        ],
        child: MaterialApp(home: SalesOrdersPage(approvalService: approvals)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inSheet(String text) => find.descendant(
    of: find.byType(SalesDocumentSheet),
    matching: find.textContaining(text),
  );

  /// A lifecycle button on the sheet, addressed by key: 'Cancelled' also
  /// contains 'Cancel', so a text finder would lie here.
  Finder sheetAction(Key key) => find.descendant(
    of: find.byType(SalesDocumentSheet),
    matching: find.byKey(key),
  );

  /// Opens one order's sheet. At 760 px the list draws CARDS, so the row itself
  /// is the tap target — there is no "View" button to press at this width.
  Future<void> openSheet(
    WidgetTester tester, [
    String number = 'SO-20261019-0001',
  ]) async {
    await tester.tap(find.text(number));
    await tester.pumpAndSettle();
  }

  group('status the rules see', () {
    testWidgets('legacy PROCESSING and READY read as Confirmed', (
      tester,
    ) async {
      sales.orders = [
        _order(id: 7, number: 'SO-A', status: 'PROCESSING'),
        _order(id: 8, number: 'SO-B', status: 'READY'),
      ];
      await pumpOrders(tester);

      expect(find.widgetWithText(StatusBadge, 'Confirmed'), findsNWidgets(2));
      expect(
        find.text('Ready'),
        findsNothing,
        reason:
            'no code path writes READY any more; showing it would invent a '
            'state the server does not have',
      );
      expect(find.text('Processing'), findsNothing);
    });

    testWidgets('PARTIAL and CANCELLED are real statuses on the list', (
      tester,
    ) async {
      sales.orders = [
        _order(id: 7, number: 'SO-A', status: 'PARTIAL'),
        _order(id: 8, number: 'SO-B', status: 'CANCELLED'),
      ];
      await pumpOrders(tester);

      // The chip bar carries the same words, so count the row BADGES.
      expect(find.widgetWithText(StatusBadge, 'Partial'), findsOneWidget);
      expect(find.widgetWithText(StatusBadge, 'Cancelled'), findsOneWidget);
    });
  });

  group('the order sheet', () {
    testWidgets('shows ordered, fulfilled and remaining per line, and the '
        'stock hint', (tester) async {
      sales.orders = [
        _order(
          status: 'PARTIAL',
          items: const [
            OrderLineItem(
              variantUomId: 501,
              qty: 10,
              unitPrice: 250,
              fulfilledQty: 4,
              remainingQty: 6,
              availableQty: 6,
            ),
          ],
        ),
      ];
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);

      expect(inSheet('Ordered 10'), findsOneWidget);
      expect(inSheet('Fulfilled 4'), findsOneWidget);
      expect(inSheet('Remaining 6'), findsOneWidget);
      expect(inSheet('Enough in stock'), findsOneWidget);
    });

    testWidgets('says how short a line is when the shop cannot cover it', (
      tester,
    ) async {
      sales.orders = [
        _order(
          items: const [
            OrderLineItem(
              variantUomId: 501,
              qty: 5,
              unitPrice: 250,
              remainingQty: 5,
              availableQty: 2,
            ),
          ],
        ),
      ];
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);

      expect(inSheet('Remaining 5'), findsOneWidget);
      expect(inSheet('Short by 3'), findsOneWidget);
    });

    testWidgets('renders without a stock hint when the wire has no '
        'available_qty (B5 not deployed)', (tester) async {
      sales.orders = [_order()];
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);

      expect(inSheet('Ordered 10'), findsOneWidget);
      expect(inSheet('Enough in stock'), findsNothing);
      expect(inSheet('Short by'), findsNothing);
    });
  });

  group('who may edit or cancel', () {
    testWidgets('a Store Manager sees Edit and Cancel on a confirmed order', (
      tester,
    ) async {
      sales.orders = [_order()];
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);

      expect(sheetAction(const ValueKey('so-sheet-edit')), findsOneWidget);
      expect(sheetAction(const ValueKey('so-sheet-cancel')), findsOneWidget);
      // Decision 19: DELETE is gone for orders; cancellation replaces it.
      expect(inSheet('Delete'), findsNothing);
    });

    testWidgets('a cashier sees neither', (tester) async {
      sales.orders = [_order()];
      await pumpOrders(tester, role: 'Cashier');
      await openSheet(tester);

      expect(find.byType(SalesDocumentSheet), findsOneWidget);
      expect(sheetAction(const ValueKey('so-sheet-edit')), findsNothing);
      expect(sheetAction(const ValueKey('so-sheet-cancel')), findsNothing);
      expect(inSheet('Delete'), findsNothing);
    });

    testWidgets('a Stock Manager sees neither', (tester) async {
      sales.orders = [_order()];
      await pumpOrders(tester, role: 'Stock Manager');
      await openSheet(tester);

      expect(find.byType(SalesDocumentSheet), findsOneWidget);
      expect(sheetAction(const ValueKey('so-sheet-edit')), findsNothing);
      expect(sheetAction(const ValueKey('so-sheet-cancel')), findsNothing);
    });

    testWidgets('a part-fulfilled order offers Cancel but NOT Edit', (
      tester,
    ) async {
      sales.orders = [
        _order(
          status: 'PARTIAL',
          items: const [
            OrderLineItem(
              variantUomId: 501,
              qty: 10,
              unitPrice: 250,
              fulfilledQty: 4,
              remainingQty: 6,
              availableQty: 6,
            ),
          ],
        ),
      ];
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);

      expect(
        sheetAction(const ValueKey('so-sheet-edit')),
        findsNothing,
        reason:
            'once a unit has been rung the lines are the record of what was '
            'promised (decision 19 #4)',
      );
      expect(sheetAction(const ValueKey('so-sheet-cancel')), findsOneWidget);
    });

    testWidgets('a completed or cancelled order offers neither', (
      tester,
    ) async {
      sales.orders = [
        _order(id: 7, number: 'SO-A', status: 'COMPLETED'),
        _order(id: 8, number: 'SO-B', status: 'CANCELLED'),
      ];
      await pumpOrders(tester, role: 'Store Manager');

      await openSheet(tester, 'SO-A');
      expect(sheetAction(const ValueKey('so-sheet-edit')), findsNothing);
      expect(sheetAction(const ValueKey('so-sheet-cancel')), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await openSheet(tester, 'SO-B');
      expect(sheetAction(const ValueKey('so-sheet-edit')), findsNothing);
      expect(sheetAction(const ValueKey('so-sheet-cancel')), findsNothing);
    });
  });

  group('editing an order', () {
    testWidgets('Edit opens the form filled with the order, and submits the '
        'whole line set with a reason', (tester) async {
      sales.orders = [_order()];
      // The service answers with the edited row, and the list re-reads it.
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);
      await tester.tap(sheetAction(const ValueKey('so-sheet-edit')));
      await tester.pumpAndSettle();

      expect(find.byType(SalesOrderFormDialog), findsOneWidget);
      expect(find.text('Edit sales order'), findsOneWidget);
      final qty = tester.widget<TextFormField>(
        find.byKey(const ValueKey('so-qty-0')),
      );
      expect(qty.controller!.text, '10');
      final price = tester.widget<TextFormField>(
        find.byKey(const ValueKey('so-price-0')),
      );
      expect(price.controller!.text, '250.00');

      await tester.enterText(find.byKey(const ValueKey('so-qty-0')), '7');
      await tester.enterText(
        find.byKey(const ValueKey('so-reason')),
        'Customer cut the order',
      );
      await tester.tap(find.byKey(const ValueKey('so-submit')));
      await tester.pumpAndSettle();

      expect(sales.edits, hasLength(1));
      expect(sales.edits.single.reason, 'Customer cut the order');
      expect(sales.edits.single.lines.single.qty, 7);
      expect(sales.edits.single.lines.single.unitPrice, 250);
      expect(find.byType(SalesOrderFormDialog), findsNothing);
    });

    testWidgets('a reason is required', (tester) async {
      sales.orders = [_order()];
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);
      await tester.tap(sheetAction(const ValueKey('so-sheet-edit')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('so-submit')));
      await tester.pumpAndSettle();

      expect(sales.edits, isEmpty);
      expect(find.byType(SalesOrderFormDialog), findsOneWidget);
    });

    testWidgets('a refused edit shows the server sentence in the dialog and '
        'keeps what was typed', (tester) async {
      sales.orders = [_order()];
      sales.editRefusal =
          'Sales order SO-20261019-0001 is PARTIAL and cannot be rewritten: '
          'only a CONFIRMED order with nothing fulfilled can be edited.';
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);
      await tester.tap(sheetAction(const ValueKey('so-sheet-edit')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('so-qty-0')), '7');
      await tester.enterText(
        find.byKey(const ValueKey('so-reason')),
        'Too late',
      );
      await tester.tap(find.byKey(const ValueKey('so-submit')));
      await tester.pumpAndSettle();

      expect(find.byType(SalesOrderFormDialog), findsOneWidget);
      expect(find.textContaining('cannot be rewritten'), findsOneWidget);
      final qty = tester.widget<TextFormField>(
        find.byKey(const ValueKey('so-qty-0')),
      );
      expect(qty.controller!.text, '7');
    });

    testWidgets('an above-cap edit asks for approval, then resubmits with the '
        'token', (tester) async {
      sales.orders = [_order()];
      sales.editRefusal =
          'This discount is 25.00 percent and the limit is 10.00. Ask a Store '
          'Manager or Admin to approve it.';
      sales.editRefusalCode = 'DISCOUNT_OVER_CAP';
      sales.editRefusalPercent = 25;
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);
      await tester.tap(sheetAction(const ValueKey('so-sheet-edit')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('so-price-0')),
        '187.50',
      );
      await tester.enterText(
        find.byKey(const ValueKey('so-reason')),
        'Agreed price',
      );
      await tester.tap(find.byKey(const ValueKey('so-submit')));
      await tester.pumpAndSettle();

      expect(find.byType(PosDiscountApprovalDialog), findsOneWidget);
      expect(approvals.asked, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Approver username'),
        'boss',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'secret',
      );
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();

      expect(approvals.asked, [25]);
      expect(sales.edits, hasLength(2));
      expect(sales.edits.first.approvalToken, isNull);
      expect(sales.edits.last.approvalToken, 'tok-1');
      expect(find.byType(SalesOrderFormDialog), findsNothing);
    });
  });

  // Phase 7 F1 fix (whole-change review, Important 1): the slip's address and
  // FEE are only correctable from this form — `/deliveries/` is read-only and no
  // delivery-edit screen ships — and the fee is billed exactly once at first
  // fulfilment, so a wrong one is a customer billed wrongly forever.
  group('editing the delivery slip', () {
    /// Turns the Deliver section on in EDIT mode and fills a whole slip: the
    /// server's `_validated_delivery` refuses a partial one.
    Future<void> fillSlip(WidgetTester tester, {String fee = '200'}) async {
      await tester.ensureVisible(
        find.byKey(const ValueKey('so-deliver-toggle')),
      );
      await tester.tap(find.byKey(const ValueKey('so-deliver-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('so-delivery-address')),
        '12 Mabini St, Cebu',
      );
      await tester.enterText(
        find.byKey(const ValueKey('so-delivery-contact')),
        'Ana Reyes',
      );
      await tester.enterText(
        find.byKey(const ValueKey('so-delivery-phone')),
        '0917 555 1234',
      );
      await tester.enterText(
        find.byKey(const ValueKey('so-delivery-fee')),
        fee,
      );
      await tester.enterText(
        find.byKey(const ValueKey('so-reason')),
        'Wrong delivery fee',
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the edit form carries the Deliver section, and a corrected fee '
        'goes on the PATCH', (tester) async {
      sales.orders = [_order()];
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);
      await tester.tap(sheetAction(const ValueKey('so-sheet-edit')));
      await tester.pumpAndSettle();

      // Same section, same keys, same validators as a create: there is no other
      // place in the product where a slip's fee or address can be corrected.
      expect(find.byKey(const ValueKey('so-deliver-toggle')), findsOneWidget);
      await fillSlip(tester);
      expect(find.byKey(const ValueKey('so-delivery-address')), findsOneWidget);
      expect(find.byKey(const ValueKey('so-delivery-contact')), findsOneWidget);
      expect(find.byKey(const ValueKey('so-delivery-phone')), findsOneWidget);
      expect(find.byKey(const ValueKey('so-delivery-fee')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('so-submit')));
      await tester.pumpAndSettle();

      expect(sales.edits, hasLength(1));
      final delivery =
          sales.edits.single.toJson()['delivery'] as Map<String, dynamic>?;
      expect(
        delivery,
        isNotNull,
        reason: 'the corrected fee must reach the slip',
      );
      expect(delivery!['fee'], '200.00');
      expect(delivery['address'], '12 Mabini St, Cebu');
      expect(delivery['contact_name'], 'Ana Reyes');
      expect(delivery['contact_phone'], '0917 555 1234');
      expect(
        delivery['scheduled_date'],
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      );
      // The reason is still required and still sent: an edit is a reasoned act.
      expect(sales.edits.single.toJson()['reason'], 'Wrong delivery fee');
    });

    testWidgets('a line edit that leaves Deliver alone sends no delivery key', (
      tester,
    ) async {
      sales.orders = [_order()];
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);
      await tester.tap(sheetAction(const ValueKey('so-sheet-edit')));
      await tester.pumpAndSettle();

      // The slip is NOT on the order wire, so this form cannot know whether one
      // exists or what state it is in. Untouched means unsent: a `delivery` key
      // from here could overwrite a slip the driver is already holding.
      await tester.enterText(find.byKey(const ValueKey('so-qty-0')), '7');
      await tester.enterText(
        find.byKey(const ValueKey('so-reason')),
        'Customer cut the order',
      );
      await tester.tap(find.byKey(const ValueKey('so-submit')));
      await tester.pumpAndSettle();

      expect(sales.edits, hasLength(1));
      expect(sales.edits.single.toJson().containsKey('delivery'), isFalse);
    });

    testWidgets('the approval resubmit still carries the corrected delivery', (
      tester,
    ) async {
      sales.orders = [_order()];
      sales.editRefusal =
          'This discount is 25.00 percent and the limit is 10.00.';
      sales.editRefusalCode = 'DISCOUNT_OVER_CAP';
      sales.editRefusalPercent = 25;
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);
      await tester.tap(sheetAction(const ValueKey('so-sheet-edit')));
      await tester.pumpAndSettle();

      await fillSlip(tester);
      await tester.tap(find.byKey(const ValueKey('so-submit')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Approver username'),
        'boss',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'secret',
      );
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();

      expect(sales.edits, hasLength(2));
      final second =
          sales.edits.last.toJson()['delivery'] as Map<String, dynamic>?;
      expect(second, isNotNull, reason: 'the retry must not drop the slip');
      expect(second!['fee'], '200.00');
      expect(sales.edits.last.toJson()['discount_approval'], 'tok-1');
    });
  });

  group('cancelling an order', () {
    testWidgets('Cancel asks for a reason and sends it', (tester) async {
      sales.orders = [_order()];
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);
      await tester.tap(sheetAction(const ValueKey('so-sheet-cancel')));
      await tester.pumpAndSettle();

      expect(find.byType(SalesOrderCancelDialog), findsOneWidget);
      // Nothing is sent without a reason: the sentence IS the audit trail.
      await tester.tap(find.byKey(const ValueKey('so-cancel-confirm')));
      await tester.pumpAndSettle();
      expect(sales.cancels, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('so-cancel-reason')),
        'Customer backed out',
      );
      await tester.tap(find.byKey(const ValueKey('so-cancel-confirm')));
      await tester.pumpAndSettle();

      expect(sales.cancels, ['Customer backed out']);
      expect(find.byType(SalesOrderCancelDialog), findsNothing);
    });

    testWidgets('a refused cancel is shown inline and keeps the reason', (
      tester,
    ) async {
      sales.orders = [_order()];
      sales.cancelRefusal =
          'Delivery DEL-20261019-0001 is OUT_FOR_DELIVERY: the goods are '
          'already on their way.';
      await pumpOrders(tester, role: 'Store Manager');
      await openSheet(tester);
      await tester.tap(sheetAction(const ValueKey('so-sheet-cancel')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('so-cancel-reason')),
        'Customer backed out',
      );
      await tester.tap(find.byKey(const ValueKey('so-cancel-confirm')));
      await tester.pumpAndSettle();

      expect(find.byType(SalesOrderCancelDialog), findsOneWidget);
      expect(find.textContaining('already on their way'), findsOneWidget);
      final reason = tester.widget<TextFormField>(
        find.byKey(const ValueKey('so-cancel-reason')),
      );
      expect(reason.controller!.text, 'Customer backed out');
    });
  });

  // Phase 7 F1 fix round (QA Medium, 2026-11-13): the approval rule is per line
  // and per role, and CREATE is where above-cap prices are most often typed. The
  // QA flow was 157.50 against a 315.00 catalogue at a 10% cap — refused inline
  // with no way to ask a manager. Create now goes through the SAME resubmit-once
  // branch as edit.
  group('creating an order above the cap', () {
    /// Opens the create form at 760 px and prices the one line 50% below the
    /// catalogue's 250.00, exactly the QA case.
    Future<void> openAboveCapCreate(WidgetTester tester) async {
      sales.orders = [_order()];
      await pumpOrders(tester, role: 'Store Manager');
      await tester.tap(find.text('New sales order'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('so-customer')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dela Cruz Construction').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('so-price-0')),
        '125.00',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('so-submit')));
      await tester.pumpAndSettle();
    }

    Future<void> approve(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Approver username'),
        'boss',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'secret',
      );
      await tester.tap(find.text('Approve discount'));
      await tester.pumpAndSettle();
    }

    testWidgets('an above-cap create opens the approval dialog, then resubmits '
        'once with the token', (tester) async {
      sales.createRefusal =
          'This discount is 50.00 percent and the limit is 10.00. Ask a Store '
          'Manager or Admin to approve it.';
      sales.createRefusalCode = 'DISCOUNT_OVER_CAP';
      sales.createRefusalPercent = 50;

      await openAboveCapCreate(tester);

      // The defect: the refusal was a dead end on create.
      expect(find.byType(PosDiscountApprovalDialog), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Approver username'),
        findsOneWidget,
      );
      expect(approvals.asked, isEmpty);

      await approve(tester);

      expect(approvals.asked, [50]);
      expect(sales.creates, hasLength(2));
      expect(
        sales.creates.first.toJson().containsKey('discount_approval'),
        isFalse,
      );
      expect(sales.creates.last.toJson()['discount_approval'], 'tok-1');
      // The retry keeps every number it was given: the manager signs THAT price.
      final retry =
          (sales.creates.last.toJson()['items'] as List).single
              as Map<String, dynamic>;
      expect(retry['unit_price'], '125.00');
      expect(find.byType(SalesOrderFormDialog), findsNothing);
    });

    testWidgets('a second above-cap refusal lands inline and keeps the input', (
      tester,
    ) async {
      sales.createRefusal =
          'This discount is 50.00 percent and the limit is 10.00. Ask a Store '
          'Manager or Admin to approve it.';
      sales.createRefusalCode = 'DISCOUNT_OVER_CAP';
      sales.createRefusalPercent = 50;
      sales.refuseEveryCreate = true;

      await openAboveCapCreate(tester);
      await approve(tester);

      // Bounded: exactly one retry, never a loop.
      expect(sales.creates, hasLength(2));
      expect(
        find.byType(PosDiscountApprovalDialog),
        findsNothing,
        reason:
            'the token is signed for that percent; a third try would '
            're-ask for the same approval',
      );
      expect(find.byType(SalesOrderFormDialog), findsOneWidget);
      expect(find.textContaining('the limit is 10.00'), findsWidgets);
      final price = tester.widget<TextFormField>(
        find.byKey(const ValueKey('so-price-0')),
      );
      expect(price.controller!.text, '125.00');
    });

    testWidgets('dismissing the approval keeps the form and the input', (
      tester,
    ) async {
      sales.createRefusal =
          'This discount is 50.00 percent and the limit is 10.00. Ask a Store '
          'Manager or Admin to approve it.';
      sales.createRefusalCode = 'DISCOUNT_OVER_CAP';
      sales.createRefusalPercent = 50;

      await openAboveCapCreate(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(PosDiscountApprovalDialog),
          matching: find.text('Cancel'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PosDiscountApprovalDialog), findsNothing);
      expect(sales.creates, hasLength(1));
      expect(find.byType(SalesOrderFormDialog), findsOneWidget);
      expect(find.textContaining('the limit is 10.00'), findsWidgets);
      final qty = tester.widget<TextFormField>(
        find.byKey(const ValueKey('so-qty-0')),
      );
      expect(qty.controller!.text, '1');
    });
  });
}
