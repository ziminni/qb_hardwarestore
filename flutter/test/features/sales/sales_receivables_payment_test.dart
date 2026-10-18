import 'dart:async';

import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubPayingRepository extends LedgerRepository {
  _StubPayingRepository() : super();

  List<LedgerEntry> rows = const [];
  int fetchCalls = 0;
  int recordCalls = 0;
  int? lastCollectibleId;
  double? lastAmount;
  Completer<void>? holdRecord;
  String? recordFailure;

  @override
  Future<List<LedgerEntry>> fetchLedgers() async {
    fetchCalls++;
    return rows;
  }

  @override
  Future<void> recordPayment({
    required int collectibleId,
    required double amountPaid,
    String paymentMethod = 'CASH',
    String? officialReceiptNo,
  }) async {
    recordCalls++;
    lastCollectibleId = collectibleId;
    lastAmount = amountPaid;
    final gate = holdRecord;
    if (gate != null) await gate.future;
    final failure = recordFailure;
    if (failure != null) throw LedgerServiceException(failure);
  }
}

LedgerEntry _entry({int id = 1, double original = 5000, double balance = 472}) =>
    LedgerEntry(
      id: id,
      customerId: 3,
      customerName: 'Dela Cruz Construction',
      transactionNo: 'TRX-20261016-0001',
      originalAmount: original,
      balanceDue: balance,
      dueDate: DateTime.now().add(const Duration(days: 30)),
      isOverdue: false,
    );

void main() {
  late _StubPayingRepository repository;
  late SalesReceivablesViewmodel viewmodel;

  setUp(() {
    repository = _StubPayingRepository();
    viewmodel = SalesReceivablesViewmodel(repository: repository);
  });

  test('a payment posts the ledger id and amount, then reloads the rows', () async {
    repository.rows = [_entry(balance: 0, original: 5000)];

    final ok = await viewmodel.recordPayment(entry: _entry(), amount: 472);

    expect(ok, isTrue);
    expect(repository.recordCalls, 1);
    expect(repository.lastCollectibleId, 1);
    expect(repository.lastAmount, 472);
    expect(viewmodel.entries.single.balanceDue, 0);
    expect(viewmodel.payError, isNull);
  });

  test('an amount above the balance never reaches the repository', () async {
    final ok = await viewmodel.recordPayment(entry: _entry(), amount: 500);

    expect(ok, isFalse);
    expect(repository.recordCalls, 0);
    expect(viewmodel.payError, contains('more than'));
  });

  test('a server refusal keeps the rows and names the refusal', () async {
    repository.rows = [_entry()];
    repository.recordFailure =
        'That payment of 500.00 is more than the 472.00 still owed on this account.';
    await viewmodel.load();

    final ok = await viewmodel.recordPayment(entry: _entry(), amount: 472);

    expect(ok, isFalse);
    expect(viewmodel.payError, contains('more than the 472.00 still owed'));
    expect(viewmodel.entries, hasLength(1));
  });

  test('a second press while the first is in flight sends nothing', () async {
    repository.rows = [_entry(balance: 0)];
    repository.holdRecord = Completer<void>();

    final first = viewmodel.recordPayment(entry: _entry(), amount: 472);
    expect(viewmodel.isPaying(1), isTrue);
    final second = await viewmodel.recordPayment(entry: _entry(), amount: 472);

    expect(second, isFalse);
    repository.holdRecord!.complete();
    expect(await first, isTrue);
    expect(repository.recordCalls, 1);
  });
}
