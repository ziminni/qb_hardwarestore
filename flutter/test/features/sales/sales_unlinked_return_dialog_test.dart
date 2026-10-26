// Phase 5 Task 3: the manager posts an unlinked return from this dialog.
// Proves the wire (no `original_transaction`), the server summary display,
// and the list reload — with stub services, never a server.

import 'package:client/data/models/customer.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/returns_service.dart';
import 'package:client/features/sales/widgets/sales_unlinked_return_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubReturnsService extends ReturnsService {
  _StubReturnsService() : super();

  Map<String, dynamic>? sent;
  int posts = 0;

  @override
  Future<ReturnResult> postUnlinkedReturn({
    required int customerId,
    required String reason,
    required String paymentMethod,
    required List<ReturnRequestLine> lines,
  }) async {
    posts++;
    sent = {
      'customer': customerId,
      'reason': reason,
      'payment_method': paymentMethod,
      'items': [for (final line in lines) line.toJson()],
    };
    return ReturnResult.fromJson(const {
      'transaction_no': 'RTN-20261026-0001',
      'refund_summary': {
        'return_value': '300.00',
        'debt_reduced': '200.00',
        'cash_refund': '100.00',
        'refund_method': 'CASH',
        'ledger_id': 7,
        'ledger_balance': '0.00',
      },
    });
  }
}

class _StubCustomerService extends CustomerService {
  _StubCustomerService() : super();

  @override
  Future<List<Customer>> fetchCustomers() async => const [
    Customer(id: 3, name: 'Dela Cruz Construction', customerType: 'FIRM'),
  ];
}

class _StubProductsService extends ProductsService {
  _StubProductsService() : super();

  @override
  Future<ProductsSnapshot> fetchCatalogue() async => const ProductsSnapshot(
    products: [
      Product(
        id: 1,
        categoryId: 1,
        categoryName: 'Cement',
        brandId: 1,
        brandName: 'Rhino',
        baseName: 'Portland Cement',
        description: '',
        imageUrl: '',
        isActive: true,
        variants: [
          ProductVariant(
            id: 5,
            productId: 1,
            baseUomId: 1,
            minStockThreshold: 1,
            maxStockLevel: 100,
            variantName: '40kg',
            baseUomCode: 'BAG',
            isActive: true,
            sellingUoms: [
              VariantUom(
                id: 8,
                variantId: 5,
                uomId: 1,
                uomCode: 'BAG',
                uomName: 'Bag',
                barcodeQr: '',
                conversionFactor: 1,
                defaultSellingPrice: 300,
              ),
            ],
          ),
        ],
      ),
    ],
    batches: [],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required _StubReturnsService returns,
  required void Function() onPosted,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: UnlinkedReturnDialog(
          returnsService: returns,
          customerService: _StubCustomerService(),
          productsService: _StubProductsService(),
          onPosted: onPosted,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('posts without original_transaction and shows the summary', (
    tester,
  ) async {
    final returns = _StubReturnsService();
    var posted = 0;
    await _pump(tester, returns: returns, onPosted: () => posted++);

    // Customer + reason + default line, then post.
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dela Cruz Construction').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for the return (required)'),
      'bag burst in transit',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Post return'));
    await tester.pumpAndSettle();

    expect(returns.posts, 1);
    expect(
      (returns.sent!['items'] as List).single,
      {'variant_id': 8, 'qty': 1.0},
    );
    expect(returns.sent!.containsKey('original_transaction'), isFalse);
    expect(returns.sent!['reason'], 'bag burst in transit');
    expect(find.textContaining('RTN-20261026-0001'), findsOneWidget);
    expect(find.textContaining('debt reduced'), findsOneWidget);
    expect(posted, 1);
  });

  testWidgets('an empty reason never reaches the server', (tester) async {
    final returns = _StubReturnsService();
    await _pump(tester, returns: returns, onPosted: () {});

    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dela Cruz Construction').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Post return'));
    await tester.pumpAndSettle();

    expect(returns.posts, 0);
    expect(find.textContaining('reason is required'), findsOneWidget);
  });
}
