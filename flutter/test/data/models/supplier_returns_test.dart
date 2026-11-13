// Phase 8 F1 (decision 20): supplier returns, what a delivery can still give
// back, and the credit note a return mints — off the wire.
//
// These fixtures are the shapes the server sends (apps/inventory: the
// `returnable` action of `GoodsReceiptViewSet`, `SupplierReturnSerializer` and
// `SupplierCreditNoteSerializer`). Every quantity and money figure is a
// 2-decimal STRING and is parsed rather than coerced; the returnable row speaks
// the receipt LINE's unit, which is the number a clerk types back.

import 'package:client/data/models/supplier_returns.dart';
import 'package:flutter_test/flutter_test.dart';

/// One row of `GET /goods-receipts/{id}/returnable/` (a bare array, not a page).
Map<String, dynamic> _returnable() => {
  'receipt_line': 31,
  'variant': 7,
  'variant_name': 'Portland Cement 40 kg',
  'unit': 'BAG',
  'delivered': '40.00',
  'returned': '5.00',
  'returnable': '35.00',
};

Map<String, dynamic> _deduction() => {
  'id': 3,
  'batch': 12,
  'qty': '2.00',
  'unit_cost_landed': '250.00',
};

Map<String, dynamic> _line() => {
  'id': 8,
  'receipt_line': 31,
  'qty': '2.00',
  'base_qty': '2.00',
  'credit_value': '500.00',
  'deductions': [_deduction()],
};

Map<String, dynamic> _return({Object? creditNoteNumber = 'CN-20261114-0001'}) =>
    {
      'id': 5,
      'receipt': 9,
      'supplier': 2,
      'supplier_name': 'Cebu Steel Works',
      'purchase_order': 41,
      'bill': 4,
      'reason': 'Torn bags',
      'created_by': 3,
      'created_by_name': 'Maria Santos',
      'created_at': '2026-11-14T08:15:00Z',
      'credit_note_number': creditNoteNumber,
      'credit_note_total': creditNoteNumber == null ? null : '500.00',
      'credit_note_remaining': creditNoteNumber == null ? null : '100.00',
      'lines': [_line()],
    };

Map<String, dynamic> _creditNote() => {
  'id': 12,
  'number': 'CN-20261114-0001',
  'supplier': 2,
  'supplier_name': 'Cebu Steel Works',
  'supplier_return': 5,
  'source_bill': 4,
  'value': '500.00',
  'vat_rate': '12.00',
  'vat_inclusive': true,
  'vat_amount': '53.57',
  'total_amount': '500.00',
  'remaining_amount': '100.00',
  'applied_amount': '400.00',
  'created_at': '2026-11-14T08:15:00Z',
};

void main() {
  group('returnable lines', () {
    test('a line answers in its own package unit, parsed as numbers', () {
      final line = SupplierReturnableLine.fromJson(_returnable());

      expect(line.receiptLineId, 31);
      expect(line.variantId, 7);
      expect(line.variantName, 'Portland Cement 40 kg');
      expect(line.unit, 'BAG');
      expect(line.delivered, 40);
      expect(line.returned, 5);
      expect(line.returnable, 35);
      expect(line.canReturn, isTrue);
    });

    test('a sold-down line offers nothing back', () {
      // The cap is min(delivered - returned, on-hand): a line whose bags were
      // sold reads 0.00 and must not offer a return the POST would refuse.
      final line = SupplierReturnableLine.fromJson({
        ..._returnable(),
        'returnable': '0.00',
      });

      expect(line.returnable, 0);
      expect(line.canReturn, isFalse);
    });

    test('a missing quantity fails instead of reading 0.00', () {
      expect(
        () =>
            SupplierReturnableLine.fromJson(_returnable()..remove('delivered')),
        throwsFormatException,
      );
    });
  });

  group('a recorded return', () {
    test('decodes the flattened credit note and its lines', () {
      final returned = SupplierReturn.fromJson(_return());

      expect(returned.id, 5);
      expect(returned.receiptId, 9);
      expect(returned.supplierId, 2);
      expect(returned.supplierName, 'Cebu Steel Works');
      expect(returned.purchaseOrderId, 41);
      expect(returned.billId, 4);
      expect(returned.reason, 'Torn bags');
      expect(returned.createdByName, 'Maria Santos');
      expect(returned.createdAt, DateTime.utc(2026, 11, 14, 8, 15));
      expect(returned.creditNoteNumber, 'CN-20261114-0001');
      expect(returned.creditNoteTotal, 500);
      expect(returned.creditNoteRemaining, 100);
    });

    test('a line carries the package qty, the base qty and its batches', () {
      final line = SupplierReturn.fromJson(_return()).lines.single;

      expect(line.id, 8);
      expect(line.receiptLineId, 31);
      expect(line.qty, 2);
      expect(line.baseQty, 2);
      expect(line.creditValue, 500);
      expect(line.deductions.single.batchId, 12);
      expect(line.deductions.single.qty, 2);
      expect(line.deductions.single.unitCostLanded, 250);
    });

    test(
      'a return from before credit notes has no note and does not crash',
      () {
        // DRF answers null for a missing reverse OneToOne, so the shape stays
        // honest for any return written before B3.
        final returned = SupplierReturn.fromJson(
          _return(creditNoteNumber: null),
        );

        expect(returned.creditNoteNumber, isNull);
        expect(returned.creditNoteTotal, isNull);
        expect(returned.creditNoteRemaining, isNull);
      },
    );

    test('a bill-less receipt decodes a null bill', () {
      final returned = SupplierReturn.fromJson({..._return(), 'bill': null});

      expect(returned.billId, isNull);
    });
  });

  group('a credit note', () {
    test('decodes its value, VAT snapshot and what is left to spend', () {
      final note = SupplierCreditNote.fromJson(_creditNote());

      expect(note.id, 12);
      expect(note.number, 'CN-20261114-0001');
      expect(note.supplierId, 2);
      expect(note.supplierName, 'Cebu Steel Works');
      expect(note.supplierReturnId, 5);
      expect(note.sourceBillId, 4);
      expect(note.value, 500);
      expect(note.vatRate, 12);
      expect(note.vatInclusive, isTrue);
      expect(note.vatAmount, 53.57);
      expect(note.totalAmount, 500);
      expect(note.remainingAmount, 100);
      expect(note.appliedAmount, 400);
    });

    test('a note with money left is open, a spent one is not', () {
      expect(SupplierCreditNote.fromJson(_creditNote()).isOpen, isTrue);
      expect(
        SupplierCreditNote.fromJson({
          ..._creditNote(),
          'remaining_amount': '0.00',
        }).isOpen,
        isFalse,
      );
    });

    test('a receipt that created no bill has no source bill', () {
      final note = SupplierCreditNote.fromJson({
        ..._creditNote(),
        'source_bill': null,
      });

      expect(note.sourceBillId, isNull);
    });

    test('a missing vat_inclusive fails instead of guessing the VAT style', () {
      // Guessing would print a VAT-exclusive note's total as if tax were inside.
      expect(
        () =>
            SupplierCreditNote.fromJson(_creditNote()..remove('vat_inclusive')),
        throwsFormatException,
      );
    });
  });
}
