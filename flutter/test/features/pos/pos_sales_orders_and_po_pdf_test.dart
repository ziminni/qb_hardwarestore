import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/views/pos_sales_orders_page.dart';
import 'package:client/features/suppliers/widgets/purchase_order_pdf.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubPosService extends PosService {
  _StubPosService(this.orders);

  final List<PosOpenOrder> orders;

  @override
  Future<List<PosOpenOrder>> fetchAllSalesOrders() async => orders;
}

class _StubCustomerService extends CustomerService {
  _StubCustomerService(this.customers);

  final List<Customer> customers;

  @override
  Future<List<Customer>> fetchCustomers({String? query}) async => customers;
}

void main() {
  group('PurchaseOrderPdf', () {
    test(
      'builds valid PDF bytes and contains order details without BIR',
      () async {
        final order = PurchaseOrder(
          id: 42,
          supplierId: 7,
          supplierName: 'Cemex Philippines',
          orderDate: DateTime(2026, 11, 25, 10, 30),
          expectedDelivery: DateTime(2026, 11, 28),
          status: PurchaseStatus.ordered,
          createdBy: 'Stocker One',
          notes: 'Deliver to Store Bay 1',
          items: const [
            PurchaseItem(
              productName: 'Portland Cement',
              variantName: '40kg Bag',
              sku: 'CEM-40',
              quantity: 50,
              receivedQuantity: 0,
              unitCost: 245.5,
              uomCode: 'BAG',
            ),
          ],
        );

        final content = purchaseOrderPdfContent(order);
        expect(content.title, 'Purchase Order PO-42');
        expect(content.kpis.map((k) => k.value), contains('Cemex Philippines'));
        expect(content.rows.first.first, contains('Portland Cement'));
        expect(content.title.toUpperCase(), isNot(contains('BIR')));
        expect(PurchaseOrderPdf.fileName(order.id), 'PO-42.pdf');

        final bytes = await renderPurchaseOrderPdf(order);
        expect(bytes, isNotEmpty);
        // PDF magic header %PDF-
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      },
    );
  });

  group('ReceiptLine unit_cost serialization', () {
    test('includes unit_cost when provided and omits when null', () {
      const withCost = ReceiptLine(poItemId: 5, qty: 10, unitCost: 275.5);
      expect(withCost.toJson()['unit_cost'], '275.50');

      const withoutCost = ReceiptLine(poItemId: 5, qty: 10);
      expect(withoutCost.toJson().containsKey('unit_cost'), isFalse);
    });
  });

  group('PosSalesOrdersPage', () {
    final orders = [
      PosOpenOrder(
        id: 1,
        number: 'SO-20261125-0001',
        customerId: 10,
        status: 'CONFIRMED',
        createdAt: DateTime(2026, 11, 25, 9, 0),
        lines: const [
          PosOpenOrderLine(
            id: 101,
            variantUomId: 500,
            qty: 10,
            unitPrice: 260,
            remainingQty: 10,
            availableQty: 50,
          ),
        ],
      ),
      PosOpenOrder(
        id: 2,
        number: 'SO-20261125-0002',
        customerId: 11,
        status: 'CANCELLED',
        createdAt: DateTime(2026, 11, 25, 8, 30),
        lines: const [
          PosOpenOrderLine(
            id: 102,
            variantUomId: 501,
            qty: 5,
            unitPrice: 150,
            remainingQty: 0,
          ),
        ],
      ),
    ];

    final customers = const [
      Customer(
        id: 10,
        name: 'Dela Cruz Construction',
        customerType: 'CONSTRUCTION_FIRM',
      ),
      Customer(
        id: 11,
        name: 'Santos Builders',
        customerType: 'CONTRACTOR',
      ),
    ];

    testWidgets(
      'lists all statuses, filters Cancelled, and completes open order at till',
      (tester) async {
        tester.view.physicalSize = const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final auth = AuthViewmodel(AuthRepository(AuthService()))
          ..user = const User(
            id: 4,
            username: 'cashier1',
            email: 'cashier1@qb.ph',
            fullName: 'Cashier One',
            role: Role(id: 4, name: 'pos', displayName: 'Cashier'),
          );
        PosOpenOrder? handedOff;
        await tester.pumpWidget(
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: auth,
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: PosSalesOrdersPage(
                posService: _StubPosService(orders),
                customerService: _StubCustomerService(customers),
                onCompleteAtTill: (order) => handedOff = order,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('SO-20261125-0001'), findsOneWidget);
        expect(find.text('Dela Cruz Construction'), findsOneWidget);
        expect(find.text('SO-20261125-0002'), findsOneWidget);
        expect(find.text('Santos Builders'), findsOneWidget);

        // Only the confirmed order has Complete at Till.
        expect(
          find.byKey(const ValueKey('pos-sales-order-complete-1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('pos-sales-order-complete-2')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey('pos-sales-order-complete-1')),
        );
        await tester.pumpAndSettle();
        expect(handedOff?.id, 1);

        // Filter to Cancelled.
        await tester.tap(
          find.descendant(
            of: find.byType(FilterBar),
            matching: find.text('Cancelled'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('SO-20261125-0002'), findsOneWidget);
        expect(find.text('SO-20261125-0001'), findsNothing);
      },
    );
  });
}
