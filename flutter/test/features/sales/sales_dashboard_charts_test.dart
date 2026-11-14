// Card M1 (wave-3b fix pass, FX4): the dashboard's two charts must state what
// they know and nothing else.
//
// The trend labelled every day in `k` thousands ("₱1141.0k", not the one money
// format D1 defines) and printed "None" under a flat bar, which reads as a
// missing fact rather than a day without sales.
//
// The top-products list showed the selling-unit CODE ("PC", "BAG"). The sales
// wire (`SalesItemSerializer`) really sends only `variant_uom` and
// `variant_uom_code` — never a product or variant name — so the name comes from
// the app-scoped catalogue the quotations and orders sheets already read
// (`variantUomName`, decision D-02), and the row falls back to the code when
// that catalogue has not been read. Both paths are pinned here.

import 'package:client/data/models/sales.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_revenue_trend.dart';
import 'package:client/features/sales/widgets/sales_top_products.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

void main() {
  testWidgets('a day with sales is labelled in pesos, a zero day is blank', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(SalesRevenueTrend(sales: _sales())));

    expect(find.text('₱1,000.00'), findsOneWidget);
    expect(find.text('₱40.50'), findsOneWidget);
    expect(
      find.text('None'),
      findsNothing,
      reason: 'a day without sales shows no label at all',
    );
    expect(find.textContaining('k'), findsNothing);
  });

  testWidgets('the labels never overflow their column', (tester) async {
    // The trend sits in a 3/5 slot on a 1100 px window and full width below
    // 820 px, so the widest peso label has to shrink rather than wrap.
    await tester.pumpWidget(
      _wrap(SizedBox(width: 360, child: SalesRevenueTrend(sales: _sales()))),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('a top product row names the product, not its unit code', (
    tester,
  ) async {
    // The catalogue is app-scoped in production and loaded by the dashboard,
    // so the manager reads "Cement Bag 40 kg" with the code beside the count
    // instead of a bare "BAG".
    final inventory = await _inventory();
    await tester.pumpWidget(
      _wrap(SalesTopProducts(sales: _sales()), inventory: inventory),
    );

    expect(find.text('Cement Bag 40 kg'), findsOneWidget);
    expect(find.text('BAG · 6 sold'), findsOneWidget);
    expect(find.text('₱1,040.50'), findsOneWidget);
    expect(
      find.text('BAG'),
      findsNothing,
      reason: 'the code alone was the bug FX4 reports',
    );
  });

  testWidgets('without a catalogue the row falls back to the unit code', (
    tester,
  ) async {
    // No provider, no catalogue: the code is the only honest label left, and
    // the row must still say what was sold rather than "Variant unit #8".
    await tester.pumpWidget(_wrap(SalesTopProducts(sales: _sales())));

    expect(find.text('BAG'), findsOneWidget);
    expect(find.text('6 sold'), findsOneWidget);
    expect(find.text('₱1,040.50'), findsOneWidget);
  });
}

/// The catalogue the dashboard resolves names against: one selling unit (id 8,
/// code BAG) of a 40 kg cement bag.
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
              name: '40 kg',
              sellingUoms: [
                variantUom(id: 8, variantId: 5, price: 200, uomCode: 'BAG'),
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

Widget _wrap(Widget child, {InventoryViewmodel? inventory}) =>
    ChangeNotifierProvider<InventoryViewmodel?>.value(
      value: inventory,
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );

/// Two completed sales in the last seven days: 6 × the BAG unit, ₱200.00 five
/// times and ₱40.50 once. The five days between have no sales at all.
List<InventorySale> _sales() => [
  _sale(DateTime(2026, 10, 31), quantity: 5, unitPrice: 200),
  _sale(DateTime(2026, 10, 27), quantity: 1, unitPrice: 40.5),
];

InventorySale _sale(
  DateTime date, {
  required double quantity,
  required double unitPrice,
}) {
  return InventorySale(
    transactionNo: 'TRX-20261031-0001',
    date: date,
    customer: 'Walk-in',
    cashier: 'Rosa Cruz',
    paymentMethod: 'Cash',
    source: 'Walk-in',
    status: InventorySaleStatus.completed,
    // The viewmodel fills all three name fields from the one code the wire
    // carries (`variant_uom_code`); the id is what the catalogue resolves.
    lines: [
      InventorySaleLine(
        variantUomId: 8,
        productName: 'BAG',
        variantName: 'BAG',
        sku: 'BAG',
        quantity: quantity,
        unitPrice: unitPrice,
      ),
    ],
  );
}
