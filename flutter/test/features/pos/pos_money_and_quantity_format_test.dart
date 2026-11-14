// Wave-3b fix pass, FX6: one format for quantities and money, everywhere.
//
// `formatQuantity` and `formatPeso` (lib/core/format/format.dart) are the app's
// single rules (D1, D7). Four places in the till and the sales sheets still
// called `toStringAsFixed`, so the same 2.5 read "2.50" there and "2.5" in the
// cart, and a peso amount showed as a bare "100.00" with no sign or grouping.

import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/pos/widgets/pos_sale_quantity_dialog.dart';
import 'package:client/features/pos/widgets/pos_underpayment_dialog.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('salesQty is the app quantity format', () {
    test('a whole quantity keeps no decimals and is grouped', () {
      expect(salesQty(1248), '1,248');
      expect(salesQty(2), '2');
    });

    test('a fractional quantity drops trailing zeros', () {
      expect(salesQty(2.5), '2.5');
      expect(salesQty(0.05), '0.05');
    });
  });

  testWidgets('the underpayment dialog writes its amounts as pesos', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PosUnderpaymentDialog(
            total: 1480,
            amountPaid: 1000,
            customerName: 'Maria Santos',
            isAnonymous: false,
          ),
        ),
      ),
    );

    expect(find.text('₱1,480.00'), findsOneWidget);
    expect(find.text('₱1,000.00'), findsOneWidget);
    expect(find.text('₱480.00'), findsOneWidget);
  });

  testWidgets('the receipt line writes its quantity as a quantity', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosReceiptDialog(
            receipt: PosReceipt(
              reference: 'TRX-20261031-0001',
              officialReceiptNumber: 'OR-20261031-0001',
              createdAt: DateTime(2026, 10, 31, 14, 14),
              lines: [_line(quantity: 2.5, unitPrice: 640)],
              paymentMethod: 'CASH',
              amountPaid: 1600,
              total: 1600,
            ),
          ),
        ),
      ),
    );

    expect(
      find.textContaining('2.5 SQM'),
      findsOneWidget,
      reason: 'the cart says 2.5, so the receipt must not say 2.50',
    );
    // Z1 (D18): the product and its variant are two parts of one line, so a
    // middle dot joins them, not an em dash.
    expect(
      find.textContaining('Marine Plywood · 3/4 in x 4 x 8 ft'),
      findsOneWidget,
    );
    expect(find.textContaining('—'), findsNothing);
  });

  testWidgets('the quantity dialog writes available stock as a quantity', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosSaleQuantityDialog(
            product: _catalogItem(availableBaseStock: 38.5),
            options: [_catalogItem(availableBaseStock: 38.5)],
          ),
        ),
      ),
    );

    expect(find.textContaining('38.5 SQM currently available'), findsOneWidget);
    // Z1 (D18): the selling-unit option is "unit · price", not "unit — price".
    expect(find.text('SQM · ₱640.00'), findsOneWidget);
    expect(find.text('SQM — ₱640.00'), findsNothing);
  });
}

PosCartLine _line({required double quantity, required double unitPrice}) =>
    PosCartLine(
      variantUomId: 1,
      productName: 'Marine Plywood',
      variantName: '3/4 in x 4 x 8 ft',
      quantity: quantity,
      unit: 'SQM',
      unitPrice: unitPrice,
      availableQuantity: 38.5,
    );

PosCatalogItem _catalogItem({required double availableBaseStock}) =>
    PosCatalogItem(
      variantUomId: 1,
      variantId: 1,
      productName: 'Marine Plywood',
      variantName: '3/4 in x 4 x 8 ft',
      unit: 'SQM',
      barcode: 'PLY-SQM',
      conversionFactor: 1,
      unitPrice: 640,
      availableBaseStock: availableBaseStock,
    );
