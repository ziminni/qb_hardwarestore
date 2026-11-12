// Phase 5 F2 (decision 18): the payables screen's data.
//
// Pinned here, away from any widget tree:
//   * overdue bills come first, then the soonest due date — the order the
//     screen exists to act on;
//   * a payment posts ONCE (a double tap must not spend the balance twice) and
//     is never reported as failed because the refresh after it failed;
//   * a refusal keeps the server's own sentence and leaves the rows alone;
//   * the money string is 2 dp, because a double can serialize as
//     399.99999999999994 and the server would refuse a payment nobody typed.

import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/repositories/payables_repository.dart';
import 'package:client/data/services/payables_service.dart';
import 'package:client/features/payables/viewmodels/payables_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

SupplierBill _bill({
  int id = 4,
  int supplierId = 2,
  String supplierName = 'Cebu Steel Works',
  DateTime? dueDate,
  double total = 900,
  double balance = 400,
  SupplierBillStatus status = SupplierBillStatus.partial,
  bool overdue = false,
  List<SupplierPayment> payments = const [],
}) => SupplierBill(
  id: id,
  receiptId: id + 5,
  purchaseOrderId: 41,
  supplierId: supplierId,
  supplierName: supplierName,
  receivedDate: DateTime(2026, 10, 1),
  termsDays: 30,
  dueDate: dueDate ?? DateTime(2026, 10, 31),
  grossAmount: 1000,
  discountAmount: 100,
  netAmount: total,
  vatableAmount: 803.57,
  vatAmount: 96.43,
  vatRate: 12,
  totalAmount: total,
  balanceAmount: balance,
  paidAmount: total - balance,
  status: status,
  isOverdue: overdue,
  payments: payments,
);

class _StubRepository extends PayablesRepository {
  _StubRepository({List<SupplierBill>? bills, List<SupplierPayable>? summary})
    : bills = bills ?? const [],
      summary = summary ?? const [];

  List<SupplierBill> bills;
  List<SupplierPayable> summary;

  String? loadFailure;
  String? payFailure;
  int fetchBillCount = 0;
  int fetchSummaryCount = 0;
  final List<Map<String, dynamic>> postedPayments = [];

  @override
  Future<List<SupplierBill>> fetchBills({
    int? supplierId,
    SupplierBillStatus? status,
    bool overdueOnly = false,
  }) async {
    if (loadFailure != null) throw PayablesServiceException(loadFailure!);
    return bills;
  }

  @override
  Future<List<SupplierPayable>> fetchSummary() async {
    fetchSummaryCount++;
    if (loadFailure != null) throw PayablesServiceException(loadFailure!);
    return summary;
  }

  @override
  Future<SupplierBill> fetchBill(int id) async {
    fetchBillCount++;
    return bills.firstWhere((bill) => bill.id == id);
  }

  @override
  Future<void> createPayment(Map<String, dynamic> body) async {
    if (payFailure != null) throw PayablesServiceException(payFailure!);
    postedPayments.add(body);
  }
}

void main() {
  test('load reads the bills and the per-supplier summary', () async {
    final repository = _StubRepository(
      bills: [_bill()],
      summary: [
        const SupplierPayable(
          supplierId: 2,
          supplierName: 'Cebu Steel Works',
          billCount: 1,
          original: 900,
          paid: 500,
          balance: 400,
          overdue: 400,
        ),
      ],
    );
    final viewmodel = PayablesViewmodel(repository: repository);

    await viewmodel.load();

    expect(viewmodel.bills, hasLength(1));
    expect(viewmodel.suppliers.single.balance, 400);
    expect(viewmodel.isLoading, isFalse);
    expect(viewmodel.loadError, isNull);
  });

  test('a failed load says why and keeps nothing invented', () async {
    final repository = _StubRepository()
      ..loadFailure = 'The bill list is down.';
    final viewmodel = PayablesViewmodel(repository: repository);

    await viewmodel.load();

    expect(viewmodel.loadError, 'The bill list is down.');
    expect(viewmodel.bills, isEmpty);
    expect(viewmodel.isLoading, isFalse);
  });

  test('overdue bills come first, then the soonest due date', () async {
    final viewmodel = PayablesViewmodel(
      repository: _StubRepository(
        bills: [
          _bill(id: 1, dueDate: DateTime(2026, 11, 20)),
          _bill(id: 2, dueDate: DateTime(2026, 10, 5)),
          _bill(id: 3, dueDate: DateTime(2026, 9, 1), overdue: true),
          _bill(id: 4, dueDate: DateTime(2026, 9, 20), overdue: true),
        ],
      ),
    );
    await viewmodel.load();

    expect(viewmodel.filteredBills().map((bill) => bill.id), [3, 4, 2, 1]);
  });

  test('the filters narrow by supplier, status and overdue', () async {
    final viewmodel = PayablesViewmodel(
      repository: _StubRepository(
        bills: [
          _bill(id: 1, supplierId: 2),
          _bill(id: 2, supplierId: 3, status: SupplierBillStatus.paid),
          _bill(id: 3, supplierId: 3, overdue: true),
        ],
      ),
    );
    await viewmodel.load();

    expect(viewmodel.filteredBills(supplierId: 3).map((bill) => bill.id), [
      3,
      2,
    ]);
    expect(
      viewmodel
          .filteredBills(status: SupplierBillStatus.paid)
          .map((bill) => bill.id),
      [2],
    );
    expect(viewmodel.filteredBills(overdueOnly: true).map((bill) => bill.id), [
      3,
    ]);
  });

  test('a payment posts a 2 dp amount, then re-reads the bill and the '
      'summary', () async {
    final repository = _StubRepository(
      bills: [_bill(balance: 400)],
      summary: [
        const SupplierPayable(
          supplierId: 2,
          supplierName: 'Cebu Steel Works',
          billCount: 1,
          original: 900,
          paid: 500,
          balance: 400,
          overdue: 400,
        ),
      ],
    );
    final viewmodel = PayablesViewmodel(repository: repository);
    await viewmodel.load();

    // The server answers with the settled bill.
    repository.bills = [_bill(balance: 0, status: SupplierBillStatus.paid)];
    repository.summary = [
      const SupplierPayable(
        supplierId: 2,
        supplierName: 'Cebu Steel Works',
        billCount: 1,
        original: 900,
        paid: 900,
        balance: 0,
        overdue: 0,
      ),
    ];

    final error = await viewmodel.pay(
      bill: viewmodel.bills.single,
      amount: 400,
      method: SupplierPaymentMethod.cash,
    );

    expect(error, isNull);
    expect(repository.postedPayments.single, {
      'bill': 4,
      'amount': '400.00',
      'method': 'CASH',
    });
    expect(repository.fetchBillCount, 1, reason: 'the bill is refreshed');
    expect(repository.fetchSummaryCount, 2, reason: 'the totals follow');
    expect(viewmodel.bills.single.balanceAmount, 0);
    expect(viewmodel.suppliers.single.balance, 0);
    expect(viewmodel.isSubmitting, isFalse);
  });

  test('a cheque payment carries its three facts', () async {
    final repository = _StubRepository(bills: [_bill()]);
    final viewmodel = PayablesViewmodel(repository: repository);
    await viewmodel.load();

    await viewmodel.pay(
      bill: viewmodel.bills.single,
      amount: 400,
      method: SupplierPaymentMethod.cheque,
      reference: 'CV-11',
      chequeNumber: '000123',
      chequeBank: 'BDO',
      chequeDate: DateTime(2026, 10, 20),
    );

    expect(repository.postedPayments.single, {
      'bill': 4,
      'amount': '400.00',
      'method': 'CHEQUE',
      'reference': 'CV-11',
      'cheque_number': '000123',
      'cheque_bank': 'BDO',
      'cheque_date': '2026-10-20',
    });
  });

  test(
    'a refusal keeps the server sentence and leaves the rows alone',
    () async {
      final repository = _StubRepository(bills: [_bill(balance: 400)])
        ..payFailure =
            'Bill #4 has 400.00 left to pay: 999.00 is more than that.';
      final viewmodel = PayablesViewmodel(repository: repository);
      await viewmodel.load();

      final error = await viewmodel.pay(
        bill: viewmodel.bills.single,
        amount: 999,
        method: SupplierPaymentMethod.cash,
      );

      expect(error, repository.payFailure);
      expect(viewmodel.payError, repository.payFailure);
      expect(viewmodel.bills.single.balanceAmount, 400);
      expect(viewmodel.isSubmitting, isFalse);
    },
  );

  test(
    'a second tap while the first payment is in flight posts nothing',
    () async {
      final repository = _StubRepository(bills: [_bill()]);
      final viewmodel = PayablesViewmodel(repository: repository);
      await viewmodel.load();
      final bill = viewmodel.bills.single;

      await Future.wait([
        viewmodel.pay(
          bill: bill,
          amount: 400,
          method: SupplierPaymentMethod.cash,
        ),
        viewmodel.pay(
          bill: bill,
          amount: 400,
          method: SupplierPaymentMethod.cash,
        ),
      ]);

      expect(repository.postedPayments, hasLength(1));
    },
  );

  test(
    'a failed refresh after a payment is not reported as a failed payment',
    () async {
      final repository = _StubRepository(bills: [_bill()]);
      final viewmodel = PayablesViewmodel(repository: repository);
      await viewmodel.load();
      repository.loadFailure = 'The refresh is down.';

      final error = await viewmodel.pay(
        bill: viewmodel.bills.single,
        amount: 400,
        method: SupplierPaymentMethod.cash,
      );

      expect(error, isNull, reason: 'the payment WAS recorded');
      expect(repository.postedPayments, hasLength(1));
    },
  );
}
