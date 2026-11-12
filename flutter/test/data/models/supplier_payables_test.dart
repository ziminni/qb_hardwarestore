// Phase 5 F2 (decision 18): supplier payables off the wire.
//
// DRF sends every DecimalField as a STRING and this file pins that the money is
// parsed rather than coerced, that a missing derived figure is COMPUTED (never
// rendered as zero), and that an unknown status fails loudly instead of being
// shown as a status it is not.

import 'package:client/data/models/supplier_payables.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _payment() => {
  'id': 7,
  'bill': 4,
  'amount': '500.00',
  'method': 'CHEQUE',
  'reference': 'CV-11',
  'cheque_number': '000123',
  'cheque_bank': 'BDO',
  'cheque_date': '2026-10-20',
  'paid_by': 3,
  'paid_by_name': 'Maria Santos',
  'paid_on': '2026-10-20T09:30:00Z',
};

Map<String, dynamic> _bill({Object? paidAmount = '500.00'}) => {
  'id': 4,
  'receipt': 9,
  'purchase_order': 41,
  'supplier': 2,
  'supplier_name': 'Cebu Steel Works',
  'received_date': '2026-10-01',
  'terms_days': 30,
  'due_date': '2026-10-31',
  'gross_amount': '1000.00',
  'discount_amount': '100.00',
  'net_amount': '900.00',
  'vatable_amount': '803.57',
  'vat_amount': '96.43',
  'vat_rate': '12.00',
  'total_amount': '900.00',
  'balance_amount': '400.00',
  'paid_amount': paidAmount,
  'status': 'PARTIAL',
  'is_overdue': true,
  'payments': [_payment()],
};

void main() {
  test('a bill decodes its money strings, terms and dates', () {
    final bill = SupplierBill.fromJson(_bill());

    expect(bill.id, 4);
    expect(bill.receiptId, 9);
    expect(bill.purchaseOrderId, 41);
    expect(bill.supplierId, 2);
    expect(bill.supplierName, 'Cebu Steel Works');
    expect(bill.receivedDate, DateTime(2026, 10, 1));
    expect(bill.termsDays, 30);
    expect(bill.dueDate, DateTime(2026, 10, 31));
    expect(bill.grossAmount, 1000);
    expect(bill.discountAmount, 100);
    expect(bill.netAmount, 900);
    expect(bill.vatableAmount, 803.57);
    expect(bill.vatAmount, 96.43);
    expect(bill.vatRate, 12);
    expect(bill.totalAmount, 900);
    expect(bill.balanceAmount, 400);
    expect(bill.paidAmount, 500);
    expect(bill.status, SupplierBillStatus.partial);
    expect(bill.isOverdue, isTrue);
    expect(bill.payments, hasLength(1));
  });

  test('a bill with no paid_amount derives it from total minus balance', () {
    final bill = SupplierBill.fromJson(_bill(paidAmount: null));

    // Never 0: a zero here would read as "nothing paid" on a partly paid bill.
    expect(bill.paidAmount, 500);
    expect(bill.balanceAmount, 400);
  });

  test('an unknown status fails loudly instead of guessing', () {
    expect(
      () => SupplierBill.fromJson({..._bill(), 'status': 'SETTLED'}),
      throwsFormatException,
    );
  });

  test('a payment carries the cheque facts and its method label', () {
    final payment = SupplierBill.fromJson(_bill()).payments.single;

    expect(payment.id, 7);
    expect(payment.billId, 4);
    expect(payment.amount, 500);
    expect(payment.method, SupplierPaymentMethod.cheque);
    expect(payment.methodLabel, 'Cheque');
    expect(payment.reference, 'CV-11');
    expect(payment.chequeNumber, '000123');
    expect(payment.chequeBank, 'BDO');
    expect(payment.chequeDate, DateTime(2026, 10, 20));
    expect(payment.paidByName, 'Maria Santos');
    expect(payment.paidOn, isNotNull);
  });

  test('an unknown method reads as its raw code, never as another method', () {
    final payment = SupplierPayment.fromJson({
      ..._payment(),
      'method': 'GCASH',
    });

    expect(payment.methodLabel, 'GCASH');
  });

  test('a cash payment has no cheque facts, and says so with nulls', () {
    final payment = SupplierPayment.fromJson({
      ..._payment(),
      'method': 'CASH',
      'cheque_number': null,
      'cheque_bank': null,
      'cheque_date': null,
    });

    expect(payment.method, SupplierPaymentMethod.cash);
    expect(payment.chequeNumber, isNull);
    expect(payment.chequeBank, isNull);
    expect(payment.chequeDate, isNull);
  });

  test(
    'a bill row from a server that sends no payment history is not a crash',
    () {
      final json = _bill()..remove('payments');

      expect(SupplierBill.fromJson(json).payments, isEmpty);
    },
  );

  test('a per-supplier summary row decodes its count and money', () {
    final row = SupplierPayable.fromJson({
      'supplier': 2,
      'supplier_name': 'Cebu Steel Works',
      'bills': 3,
      'original': '3000.00',
      'paid': '1000.00',
      'balance': '2000.00',
      'overdue': '500.00',
    });

    expect(row.supplierId, 2);
    expect(row.supplierName, 'Cebu Steel Works');
    expect(row.billCount, 3);
    expect(row.original, 3000);
    expect(row.paid, 1000);
    expect(row.balance, 2000);
    expect(row.overdue, 500);
  });

  test('a bill knows whether it can still be paid', () {
    expect(SupplierBill.fromJson(_bill()).canPay, isTrue);
    expect(
      SupplierBill.fromJson({
        ..._bill(),
        'status': 'PAID',
        'balance_amount': '0.00',
      }).canPay,
      isFalse,
      reason: 'a settled bill must not offer a Pay button that only refuses',
    );
  });
}
