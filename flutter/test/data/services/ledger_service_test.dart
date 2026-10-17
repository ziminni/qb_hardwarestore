// Phase 4 task 7: the receivables screen stops reading a mock list.
//
// This is the first REAL data behind /sales/receivables. The behaviours worth pinning are the
// ones where a wrong answer looks like a valid one: a failed fetch that renders as "no
// receivables" (a screen that hides money), a paginated list read only on page 1 (a total that
// is simply too small), and a `paid` figure summed from the nested RECENT payments instead of
// derived (an older part-settled debt shown as bigger than it is).

import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  HttpClientAdapter? replaced;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _row({
  int id = 1,
  String customerName = 'Dela Cruz Construction',
  String transactionNo = 'TRX-20261016-0001',
  String original = '5000.00',
  String balance = '472.00',
  String dueDate = '2026-11-15',
  bool isOverdue = false,
}) => {
  'id': id,
  'customer': 3,
  'customer_name': customerName,
  'transaction': 9,
  'transaction_no': transactionNo,
  'original_amount': original,
  'balance_due': balance,
  'due_date': dueDate,
  'is_overdue': isOverdue,
  'recent_payments': [
    {'id': 1, 'amount_paid': '100.00', 'payment_method': 'CASH'},
  ],
};

void main() {
  late ApiClient client;
  late _FakeAdapter adapter;
  var requestedPages = <String>[];

  // init() is NOT idempotent - dio is `late final`, so a second call throws
  // "Field 'dio' has already been initialized". setUp runs PER TEST, so the instance is
  // initialized once here and only its adapter is swapped per test.
  setUpAll(() {
    client = ApiClient.instance..init();
  });

  setUp(() {
    requestedPages = [];
  });

  void serve(ResponseBody Function(RequestOptions options) respond) {
    adapter = _FakeAdapter(respond);
    adapter.replaced = client.dio.httpClientAdapter;
    client.dio.httpClientAdapter = adapter;
  }

  tearDown(() {
    if (adapter.replaced != null) client.dio.httpClientAdapter = adapter.replaced!;
  });

  test('parses a ledger row, deriving what was paid from the original and the balance', () async {
    serve((options) {
      requestedPages.add('${options.queryParameters['page']}');
      return _json({'count': 1, 'next': null, 'results': [_row()]});
    });

    final entries = await LedgerService(client: client).fetchLedgers();

    expect(entries, hasLength(1));
    final entry = entries.single;
    expect(entry.customerName, 'Dela Cruz Construction');
    expect(entry.transactionNo, 'TRX-20261016-0001');
    expect(entry.originalAmount, 5000);
    expect(entry.balanceDue, 472);
    expect(
      entry.paidAmount,
      4528,
      reason: 'derived from original - balance, NOT summed from recent_payments (100)',
    );
    expect(entry.dueDate, DateTime.parse('2026-11-15'));
    expect(entry.isOverdue, isFalse);
    expect(requestedPages, contains('1'));
  });

  test('follows the pages, so a long ledger is not silently cut off', () async {
    serve((options) {
      requestedPages.add('${options.queryParameters['page']}');
      final page = options.queryParameters['page'];
      if (page == 1) {
        return _json({
          'count': 2,
          'next': 'http://x/api/v1/ledgers/?page=2',
          'results': [_row(id: 1)],
        });
      }
      return _json({
        'count': 2,
        'next': null,
        'results': [_row(id: 2, customerName: 'Maria Santos', dueDate: '2026-10-01')],
      });
    });

    final entries = await LedgerService(client: client).fetchLedgers();

    expect(entries.map((e) => e.id), [1, 2], reason: 'both pages are read');
    expect(requestedPages, ['1', '2']);
  });

  test('a server failure is an error, never an empty list', () async {
    serve((_) => _json({'detail': 'boom'}, status: 500));

    await expectLater(
      LedgerService(client: client).fetchLedgers(),
      throwsA(
        isA<LedgerServiceException>().having(
          (e) => e.message,
          'message',
          isNot(contains('0')),
        ),
      ),
    );
  });

  test('an unreachable server says so in words a cashier can act on', () async {
    serve(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(
      LedgerService(client: client).fetchLedgers(),
      throwsA(
        isA<LedgerServiceException>().having(
          (e) => e.message,
          'message',
          'Cannot connect to the BuildPro server.',
        ),
      ),
    );
  });

  group('statusAt', () {
    final now = DateTime.parse('2026-10-17T09:00:00');

    LedgerEntry due(String date, {bool isOverdue = false}) => LedgerEntry(
      id: 1,
      customerId: 1,
      customerName: 'C',
      transactionNo: 'T',
      originalAmount: 100,
      balanceDue: 100,
      dueDate: DateTime.parse(date),
      isOverdue: isOverdue,
    );

    test('the server calling it overdue wins, even when the date is in the future', () {
      expect(
        due('2026-12-01', isOverdue: true).statusAt(now),
        LedgerStatus.overdue,
        reason: 'a receivable the server calls overdue must never render as current',
      );
    });

    test('a past due date is overdue even when the server flag is false', () {
      expect(due('2026-10-01').statusAt(now), LedgerStatus.overdue);
    });

    test('within the window is due soon, beyond it is current', () {
      expect(due('2026-10-20').statusAt(now), LedgerStatus.dueSoon);
      expect(due('2026-12-01').statusAt(now), LedgerStatus.current);
    });
  });
}
