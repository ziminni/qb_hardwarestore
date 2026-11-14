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
import 'package:client/data/models/supplier_returns.dart';
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

  List<SupplierCreditNote> creditNotes = const [];
  List<SupplierPayment> paymentRows = const [];
  String? creditFailure;
  String? chequeFailure;

  /// The code a decision answers with, when it must be refused.
  String? decisionCode;
  int fetchCreditNotesCount = 0;
  int fetchChequesCount = 0;
  final List<int> cleared = [];
  final List<(int, String)> bounced = [];

  @override
  Future<List<SupplierCreditNote>> fetchCreditNotes({
    int? supplierId,
    bool openOnly = false,
  }) async {
    fetchCreditNotesCount++;
    if (creditFailure != null) throw PayablesServiceException(creditFailure!);
    return creditNotes;
  }

  @override
  Future<List<SupplierPayment>> fetchCheques({
    int? supplierId,
    SupplierPaymentStatus? status,
  }) async {
    fetchChequesCount++;
    if (chequeFailure != null) throw PayablesServiceException(chequeFailure!);
    return paymentRows;
  }

  @override
  Future<SupplierPayment> clearCheque(int paymentId) async {
    if (decisionCode != null) {
      throw PayablesServiceException(
        'Cheque 000123 is already cleared.',
        code: decisionCode,
      );
    }
    cleared.add(paymentId);
    return _decided(paymentId, SupplierPaymentStatus.cleared);
  }

  @override
  Future<SupplierPayment> bounceCheque(int paymentId, String reason) async {
    if (decisionCode != null) {
      throw PayablesServiceException(
        'Cheque 000123 is already cleared.',
        code: decisionCode,
      );
    }
    bounced.add((paymentId, reason));
    return _decided(paymentId, SupplierPaymentStatus.bounced);
  }

  /// The server's answer after a decision: the same row, newly stamped.
  SupplierPayment _decided(int id, SupplierPaymentStatus status) {
    final row = paymentRows.firstWhere((payment) => payment.id == id);
    return SupplierPayment(
      id: row.id,
      billId: row.billId,
      amount: row.amount,
      method: row.method,
      methodCode: row.methodCode,
      reference: row.reference,
      chequeNumber: row.chequeNumber,
      chequeBank: row.chequeBank,
      chequeDate: row.chequeDate,
      paidByName: row.paidByName,
      paidOn: row.paidOn,
      status: status,
      statusCode: status.code,
      decidedByName: 'Maria Santos',
      decidedAt: DateTime(2026, 11, 13),
      decisionReason: status == SupplierPaymentStatus.bounced
          ? 'Insufficient funds'
          : '',
    );
  }
}

SupplierCreditNote _note({
  int id = 12,
  int supplierId = 2,
  double total = 300,
  double remaining = 200,
}) => SupplierCreditNote(
  id: id,
  number: 'CN-20261113-000$id',
  supplierId: supplierId,
  supplierName: supplierId == 2 ? 'Cebu Steel Works' : 'Bohol Lumber',
  supplierReturnId: 3,
  sourceBillId: 4,
  value: 267.86,
  vatRate: 12,
  vatInclusive: true,
  vatAmount: 32.14,
  totalAmount: total,
  remainingAmount: remaining,
  appliedAmount: total - remaining,
  createdAt: DateTime(2026, 11, 13),
);

SupplierPayment _payment({
  int id = 7,
  int billId = 4,
  double amount = 400,
  SupplierPaymentMethod method = SupplierPaymentMethod.cheque,
  SupplierPaymentStatus? status = SupplierPaymentStatus.issued,
  DateTime? chequeDate,
}) => SupplierPayment(
  id: id,
  billId: billId,
  amount: amount,
  method: method,
  methodCode: method.code,
  reference: '',
  chequeNumber: method == SupplierPaymentMethod.cheque ? '000123' : null,
  chequeBank: method == SupplierPaymentMethod.cheque ? 'BDO' : null,
  chequeDate: method == SupplierPaymentMethod.cheque
      ? (chequeDate ?? DateTime(2026, 10, 20))
      : null,
  paidByName: 'Maria Santos',
  paidOn: DateTime(2026, 10, 20),
  status: status,
  statusCode: status?.code ?? '',
);

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

  // Phase 8 F3 (decision 20): the credit-note picker and the cheque queue.
  group('supplier credit', () {
    test(
      'the open notes of one supplier are what Apply credit offers',
      () async {
        final repository = _StubRepository()
          ..creditNotes = [
            _note(id: 12, remaining: 200),
            _note(id: 13, remaining: 0, total: 100),
            _note(id: 14, supplierId: 3, remaining: 50),
          ];
        final viewmodel = PayablesViewmodel(repository: repository);

        await viewmodel.ensureCreditNotes();

        expect(viewmodel.openCreditNotesFor(2).map((note) => note.id), [
          12,
        ], reason: "a spent note and another supplier's note are not offered");
        expect(
          viewmodel.creditNotes,
          hasLength(3),
          reason: 'the tab shows all',
        );
      },
    );

    test('the notes are read once, not on every pay dialog', () async {
      final repository = _StubRepository()..creditNotes = [_note()];
      final viewmodel = PayablesViewmodel(repository: repository);

      await viewmodel.ensureCreditNotes();
      await viewmodel.ensureCreditNotes();

      expect(repository.fetchCreditNotesCount, 1);
    });

    test('a failed read is retried next time and says why', () async {
      final repository = _StubRepository()..creditFailure = 'Credit is down.';
      final viewmodel = PayablesViewmodel(repository: repository);

      await viewmodel.ensureCreditNotes();
      expect(viewmodel.creditNotesError, 'Credit is down.');

      repository.creditFailure = null;
      await viewmodel.ensureCreditNotes();

      expect(repository.fetchCreditNotesCount, 2);
      expect(viewmodel.creditNotesError, isNull);
    });

    test('applying credit posts a CREDIT payment naming the note', () async {
      final repository = _StubRepository(bills: [_bill(balance: 400)])
        ..creditNotes = [_note(remaining: 200)];
      final viewmodel = PayablesViewmodel(repository: repository);
      await viewmodel.load();
      await viewmodel.ensureCreditNotes();

      repository.bills = [_bill(balance: 200)];
      repository.creditNotes = [_note(remaining: 0, total: 300)];

      final error = await viewmodel.pay(
        bill: viewmodel.bills.single,
        amount: 200,
        method: SupplierPaymentMethod.credit,
        creditNoteId: 12,
      );

      expect(error, isNull);
      expect(repository.postedPayments.single, {
        'bill': 4,
        'amount': '200.00',
        'method': 'CREDIT',
        'credit_note': 12,
      });
      expect(
        repository.fetchCreditNotesCount,
        2,
        reason: "the note's remaining changed, so it is re-read",
      );
      expect(viewmodel.creditNotes.single.remainingAmount, 0);
      expect(viewmodel.bills.single.balanceAmount, 200);
    });
  });

  group('supplier cheque queue', () {
    test('the queue holds cheques only, oldest cheque date first', () async {
      final repository = _StubRepository()
        ..paymentRows = [
          _payment(id: 7, chequeDate: DateTime(2026, 10, 20)),
          _payment(
            id: 8,
            method: SupplierPaymentMethod.cash,
            status: SupplierPaymentStatus.cleared,
          ),
          _payment(id: 9, chequeDate: DateTime(2026, 10, 1)),
        ];
      final viewmodel = PayablesViewmodel(repository: repository);

      await viewmodel.ensureCheques();

      expect(viewmodel.cheques.map((cheque) => cheque.id), [
        9,
        7,
      ], reason: 'cash is not a cheque, and the oldest cheque is chased first');
    });

    test('the status chip narrows the queue', () async {
      final repository = _StubRepository()
        ..paymentRows = [
          _payment(id: 7),
          _payment(id: 8, status: SupplierPaymentStatus.cleared),
        ];
      final viewmodel = PayablesViewmodel(repository: repository);
      await viewmodel.ensureCheques();

      viewmodel.setChequeStatusFilter(SupplierPaymentStatus.issued);
      expect(viewmodel.filteredCheques.map((cheque) => cheque.id), [7]);

      viewmodel.setChequeStatusFilter(null);
      expect(viewmodel.filteredCheques, hasLength(2));
    });

    test('clearing a cheque replaces its row and re-reads the bills', () async {
      final repository = _StubRepository(bills: [_bill(balance: 0)])
        ..paymentRows = [_payment(id: 7)];
      final viewmodel = PayablesViewmodel(repository: repository);
      await viewmodel.load();
      await viewmodel.ensureCheques();

      final ok = await viewmodel.clearCheque(viewmodel.cheques.single);

      expect(ok, isTrue);
      expect(repository.cleared, [7]);
      expect(viewmodel.cheques.single.status, SupplierPaymentStatus.cleared);
      expect(viewmodel.decisionError, isNull);
    });

    test('a bounce puts the money back, so the bill is re-read', () async {
      final repository = _StubRepository(bills: [_bill(balance: 0)])
        ..paymentRows = [_payment(id: 7)];
      final viewmodel = PayablesViewmodel(repository: repository);
      await viewmodel.load();
      await viewmodel.ensureCheques();

      // The server restored the balance the cheque had settled.
      repository.bills = [_bill(balance: 400)];

      final ok = await viewmodel.bounceCheque(
        viewmodel.cheques.single,
        'Insufficient funds',
      );

      expect(ok, isTrue);
      expect(repository.bounced.single, (7, 'Insufficient funds'));
      expect(viewmodel.bills.single.balanceAmount, 400);
      expect(viewmodel.cheques.single.status, SupplierPaymentStatus.bounced);
    });

    test('a second decision reloads the queue and says so', () async {
      final repository = _StubRepository(bills: [_bill(balance: 0)])
        ..paymentRows = [_payment(id: 7)];
      final viewmodel = PayablesViewmodel(repository: repository);
      await viewmodel.load();
      await viewmodel.ensureCheques();
      repository
        ..decisionCode = 'CHEQUE_ALREADY_DECIDED'
        ..paymentRows = [
          _payment(id: 7, status: SupplierPaymentStatus.cleared),
        ];

      final ok = await viewmodel.clearCheque(viewmodel.cheques.single);

      expect(ok, isFalse);
      expect(viewmodel.decisionError, 'Cheque 000123 is already cleared.');
      expect(repository.fetchChequesCount, 2, reason: 'the rows are now wrong');
      expect(viewmodel.cheques.single.status, SupplierPaymentStatus.cleared);
    });

    test('a decision in flight is not sent twice', () async {
      final repository = _StubRepository()..paymentRows = [_payment(id: 7)];
      final viewmodel = PayablesViewmodel(repository: repository);
      await viewmodel.ensureCheques();
      final cheque = viewmodel.cheques.single;

      await Future.wait([
        viewmodel.clearCheque(cheque),
        viewmodel.clearCheque(cheque),
      ]);

      expect(repository.cleared, hasLength(1));
    });
  });
}
