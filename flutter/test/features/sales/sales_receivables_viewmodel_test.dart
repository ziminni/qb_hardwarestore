// Task 19 (review finding 13): SalesReceivablesViewmodel had ZERO tests.
//
// The ruling it encodes - "a failed load KEEPS the rows it already had, and the empty message
// then reads 'Receivables could not be loaded' rather than 'No receivables available'" - was
// verified by READING the code. On a money screen that is not good enough: emptying the table
// states "this store is owed nothing", which is a far more dangerous claim than "this did not
// load", and it is the one a cashier is least equipped to doubt.

import 'dart:async';

import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubLedgerRepository extends LedgerRepository {
  _StubLedgerRepository() : super();

  List<LedgerEntry> rows = const [];
  List<LedgerPayment> paymentRows = const [];
  List<PaymentReceipt> receiptRows = const [];
  String? failureMessage;
  String? paymentsFailureMessage;
  String? receiptsFailureMessage;
  int calls = 0;

  /// Gates a load in flight, so `isLoading` is observable rather than inferred.
  Completer<void>? hold;

  @override
  Future<List<LedgerEntry>> fetchLedgers() async {
    calls++;
    final gate = hold;
    if (gate != null) await gate.future;
    final failure = failureMessage;
    if (failure != null) throw LedgerServiceException(failure);
    return rows;
  }

  @override
  Future<List<LedgerPayment>> fetchPayments({String? search}) async {
    final failure = paymentsFailureMessage;
    if (failure != null) throw LedgerServiceException(failure);
    return paymentRows;
  }

  @override
  Future<List<PaymentReceipt>> fetchPaymentReceipts({String? status}) async {
    final failure = receiptsFailureMessage;
    if (failure != null) throw LedgerServiceException(failure);
    return receiptRows;
  }
}

LedgerEntry _entry({
  int id = 1,
  double original = 5000,
  double balance = 472,
  DateTime? dueDate,
  bool isOverdue = false,
}) => LedgerEntry(
  id: id,
  customerId: 3,
  customerName: 'Dela Cruz Construction',
  transactionNo: 'TRX-20261016-0001',
  originalAmount: original,
  balanceDue: balance,
  dueDate: dueDate ?? appClock.now().add(const Duration(days: 30)),
  isOverdue: isOverdue,
);

void main() {
  late _StubLedgerRepository repository;
  late SalesReceivablesViewmodel viewmodel;

  setUp(() {
    repository = _StubLedgerRepository();
    viewmodel = SalesReceivablesViewmodel(repository: repository);
  });

  test('starts empty and not loading', () {
    expect(viewmodel.entries, isEmpty);
    expect(viewmodel.isLoading, isFalse);
    expect(viewmodel.loadError, isNull);
    expect(viewmodel.outstanding, 0);
  });

  // Phase 5 Task 3: status filter chips narrow the rows client-side via
  // `statusAt` — the same source the tiles use, so the tile and the rows
  // cannot disagree about which debts are late.
  test('an overdue chip narrows to late debts only', () async {
    repository.rows = [
      _entry(id: 1, isOverdue: true),
      _entry(id: 2, dueDate: appClock.now().add(const Duration(days: 30))),
    ];
    await viewmodel.load();

    viewmodel.setStatusFilter(LedgerStatus.overdue);

    expect(viewmodel.filteredEntries.map((e) => e.id), [1]);
  });

  test('clearing the filter shows every row again', () async {
    repository.rows = [_entry(id: 1, isOverdue: true), _entry(id: 2)];
    await viewmodel.load();
    viewmodel.setStatusFilter(LedgerStatus.overdue);

    viewmodel.setStatusFilter(null);

    expect(viewmodel.filteredEntries, hasLength(2));
  });

  test('a successful load exposes the rows and totals what is owed', () async {
    repository.rows = [_entry(), _entry(id: 2, balance: 100, original: 100)];

    await viewmodel.load();

    expect(viewmodel.entries, hasLength(2));
    expect(viewmodel.outstanding, 572);
    expect(viewmodel.loadError, isNull);
    expect(viewmodel.hasEntries, isTrue);
  });

  test('overdue totals only the rows that are actually overdue', () async {
    repository.rows = [
      _entry(id: 1, balance: 472),
      _entry(id: 2, balance: 100, isOverdue: true),
      _entry(
        id: 3,
        balance: 28,
        dueDate: appClock.now().subtract(const Duration(days: 1)),
      ),
    ];

    await viewmodel.load();

    expect(
      viewmodel.overdue,
      128,
      reason:
          'the server flag and the due date both count, and the tile must agree with the rows',
    );
    expect(viewmodel.outstanding, 600);
  });

  test('isLoading is true WHILE in flight', () async {
    repository.rows = [_entry()];
    repository.hold = Completer<void>();

    final inFlight = viewmodel.load();
    expect(viewmodel.isLoading, isTrue);

    repository.hold!.complete();
    await inFlight;
    expect(viewmodel.isLoading, isFalse);
  });

  test('a failed load keeps the rows it already had', () async {
    // The dangerous alternative: emptying the table states "owed nothing".
    repository.rows = [_entry(balance: 472)];
    await viewmodel.load();
    expect(viewmodel.outstanding, 472);

    repository.failureMessage = 'The receivables could not be loaded.';
    await viewmodel.load();

    expect(viewmodel.loadError, 'The receivables could not be loaded.');
    expect(
      viewmodel.entries,
      hasLength(1),
      reason: 'a failed REFRESH must not erase what it already knew',
    );
    expect(viewmodel.outstanding, 472);
  });

  test('a retry after a failure clears the error', () async {
    repository.failureMessage = 'The receivables could not be loaded.';
    await viewmodel.load();
    expect(viewmodel.loadError, isNotNull);

    repository.failureMessage = null;
    repository.rows = [_entry()];
    await viewmodel.load();

    expect(viewmodel.loadError, isNull);
    expect(viewmodel.entries, hasLength(1));
  });

  test(
    'a non-service failure still becomes something a cashier can read',
    () async {
      // A malformed body throws FormatException, not LedgerServiceException; an unhandled type
      // would reach the UI as an unreadable error or an empty screen.
      repository.rows = const [];
      final throwing = _ThrowingRepository();
      final vm = SalesReceivablesViewmodel(repository: throwing);

      await vm.load();

      expect(vm.loadError, isNotNull);
      expect(vm.loadError, isNot(contains('FormatException')));
    },
  );

  test('loads payments and filters receipts while preserving stale rows on error', () async {
    repository.rows = [_entry(id: 1, balance: 0)];
    repository.paymentRows = [
      LedgerPayment(
        id: 10,
        collectibleId: 1,
        customerName: 'Dela Cruz Construction',
        transactionNo: 'TRX-001',
        amountPaid: 500,
        paymentMethod: 'CASH',
        paymentDate: DateTime(2026, 11, 15, 10, 0),
        officialReceiptNo: 'OR-1',
        processedByName: 'Cashier',
      ),
    ];
    repository.receiptRows = [
      PaymentReceipt(
        id: 1,
        cpmsPaymentId: 'PAY-1',
        cpmsProjectId: 'PRJ-1',
        projectName: 'Tower A',
        customerName: 'Dela Cruz Construction',
        amount: 500,
        paymentMethod: 'GCASH',
        referenceNo: 'GC-1',
        notes: '',
        submittedByName: 'Liza',
        status: 'WAITING',
        declineReason: '',
        createdAt: DateTime(2026, 11, 15, 9, 0),
      ),
      PaymentReceipt(
        id: 2,
        cpmsPaymentId: 'PAY-2',
        cpmsProjectId: 'PRJ-1',
        projectName: 'Tower A',
        customerName: 'Dela Cruz Construction',
        amount: 700,
        approvedAmount: 700,
        paymentMethod: 'BANK_TRANSFER',
        referenceNo: 'BDO-2',
        notes: '',
        submittedByName: 'Liza',
        status: 'APPROVED',
        declineReason: '',
        createdAt: DateTime(2026, 11, 14, 9, 0),
      ),
    ];

    await viewmodel.load();

    expect(viewmodel.payments, hasLength(1));
    expect(viewmodel.paymentsError, isNull);
    expect(viewmodel.filteredPaymentReceipts, hasLength(2));

    viewmodel.setReceiptStatusFilter('APPROVED');
    expect(viewmodel.filteredPaymentReceipts.map((r) => r.id), [2]);

    viewmodel.setStatusFilter(LedgerStatus.paid);
    expect(viewmodel.filteredEntries.map((e) => e.id), [1]);

    repository.paymentsFailureMessage = 'Payment history failed.';
    repository.receiptsFailureMessage = 'Receipts failed.';
    await viewmodel.load();

    expect(viewmodel.paymentsError, 'Payment history failed.');
    expect(viewmodel.receiptsError, 'Receipts failed.');
    expect(viewmodel.payments, hasLength(1));
    expect(viewmodel.paymentReceipts, hasLength(2));
  });
}

class _ThrowingRepository extends LedgerRepository {
  _ThrowingRepository() : super();

  @override
  Future<List<LedgerEntry>> fetchLedgers() async =>
      throw const FormatException('bad body');
}
