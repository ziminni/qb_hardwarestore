// Phase 9 F2 (decision 21 §2/§4): a sale can leave the shop from more than one
// shelf, and the paper and the screen must say so. The receipt is what the
// customer carries, so "Pick up: 3 PC at Store, 2 PC at Bodega" is a fact from
// the server's deduction rows - not the product's label repeated.

import 'package:client/data/models/pick_up.dart';
// `PosCheckoutResult` exists in BOTH libraries; the sale RESPONSE this test reads
// is the services one, so the model file's stale copy is hidden.
import 'package:client/data/models/pos_transaction.dart' hide PosCheckoutResult;
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _store = PickUpPart(
  locationId: 1,
  locationName: 'Store',
  qty: 3,
  unit: 'PC',
);
const _bodega = PickUpPart(
  locationId: 2,
  locationName: 'Bodega',
  qty: 2,
  unit: 'PC',
);

PosReceipt _receipt({
  List<PickUpPart> pickUp = const [_store, _bodega],
  String storedAtName = 'Bodega',
}) => PosReceipt(
  reference: 'TRX-20261114-0007',
  officialReceiptNumber: 'OR-20261114-0007',
  createdAt: DateTime(2026, 11, 14, 10),
  lines: [
    PosCartLine(
      variantUomId: 1,
      productName: 'Portland Cement',
      variantName: '40kg',
      quantity: 5,
      unit: 'BAG',
      unitPrice: 450,
      availableQuantity: 10,
      storedAtName: storedAtName,
      pickUp: pickUp,
    ),
  ],
  paymentMethod: 'CASH',
  amountPaid: 2250,
  total: 2250,
);

void main() {
  group('the 80 mm receipt', () {
    test('names both shelves the line left', () {
      expect(
        ReceiptContent(_receipt()).lines.single.pickUp,
        'Pick up: 3 PC at Store, 2 PC at Bodega',
      );
    });

    test('an old wire keeps the plain caption', () {
      expect(
        ReceiptContent(_receipt(pickUp: const [])).lines.single.pickUp,
        'Pick up at Bodega',
      );
    });

    test('neither a split nor a place prints nothing', () {
      expect(
        ReceiptContent(
          _receipt(pickUp: const [], storedAtName: ''),
        ).lines.single.pickUp,
        isNull,
      );
    });
  });

  group('the on-screen receipt', () {
    testWidgets('prints the split under its item', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PosReceiptDialog(receipt: _receipt())),
        ),
      );

      expect(
        find.text('Pick up: 3 PC at Store, 2 PC at Bodega'),
        findsOneWidget,
      );
    });

    testWidgets('an old wire prints the plain caption', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosReceiptDialog(receipt: _receipt(pickUp: const [])),
          ),
        ),
      );

      expect(find.text('Pick up at Bodega'), findsOneWidget);
    });
  });

  group('the checkout answer', () {
    test('carries each line\'s pick_up through to the receipt', () {
      final result = PosCheckoutResult.fromJson(const {
        'id': 38,
        'transaction_no': 'TRX-20261114-0038',
        'trans_date': '2026-11-14T12:00:00Z',
        'grand_total': '2250.00',
        'receipt': {'or_number': 'OR-20261114-0038'},
        'items': [
          {
            'variant_uom': 1,
            'qty': '5.00',
            'unit_price': '450.00',
            'subtotal': '2250.00',
            'stored_at_name': 'Bodega',
            'pick_up': [
              {
                'location': 1,
                'location_name': 'Store',
                'qty': '3.00',
                'unit': 'BAG',
              },
              {
                'location': 2,
                'location_name': 'Bodega',
                'qty': '2.00',
                'unit': 'BAG',
              },
            ],
          },
        ],
      });

      final line = result.lines.single;
      expect(line.pickUp, hasLength(2));
      expect(line.pickUp.first.locationName, 'Store');
      expect(line.pickUp.last.qty, 2);
    });

    test('a pre-Phase-9 answer decodes to no parts', () {
      final result = PosCheckoutResult.fromJson(const {
        'id': 39,
        'transaction_no': 'TRX-20261114-0039',
        'trans_date': '2026-11-14T12:00:00Z',
        'grand_total': '450.00',
        'receipt': {'or_number': 'OR-20261114-0039'},
        'items': [
          {
            'variant_uom': 1,
            'qty': '1.00',
            'unit_price': '450.00',
            'subtotal': '450.00',
            'stored_at_name': 'Bodega',
          },
        ],
      });

      expect(result.lines.single.pickUp, isEmpty);
    });
  });
}
