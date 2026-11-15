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
  String? projectName,
}) => {
  'id': id,
  'customer': 3,
  'customer_name': customerName,
  // Absent on a counter sale's utang, exactly as the server sends it.
  'project_name': ?projectName,
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
    if (adapter.replaced != null) {
      client.dio.httpClientAdapter = adapter.replaced!;
    }
  });

  test(
    'parses a ledger row, deriving what was paid from the original and the balance',
    () async {
      serve((options) {
        requestedPages.add('${options.queryParameters['page']}');
        return _json({
          'count': 1,
          'next': null,
          'results': [_row()],
        });
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
        reason:
            'derived from original - balance, NOT summed from recent_payments (100)',
      );
      expect(entry.dueDate, DateTime.parse('2026-11-15'));
      expect(entry.isOverdue, isFalse);
      expect(requestedPages, contains('1'));
    },
  );

  test(
    'a release-made utang carries the project it was released for',
    () async {
      serve(
        (_) => _json({
          'count': 1,
          'next': null,
          'results': [_row(projectName: '2-Storey House Mandaue')],
        }),
      );

      final entries = await LedgerService(client: client).fetchLedgers();

      expect(
        entries.single.projectName,
        '2-Storey House Mandaue',
        reason: 'decision 03: the utang says which project owes it',
      );
    },
  );

  test(
    'a counter sale utang has no project, and the missing key is not an error',
    () async {
      serve(
        (_) => _json({
          'count': 1,
          'next': null,
          'results': [_row()],
        }),
      );

      final entries = await LedgerService(client: client).fetchLedgers();

      expect(
        entries.single.projectName,
        isNull,
        reason:
            'walk-in and counter sales carry no project, so null is the answer',
      );
    },
  );

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
        'results': [
          _row(id: 2, customerName: 'Maria Santos', dueDate: '2026-10-01'),
        ],
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

    LedgerEntry due(
      String date, {
      bool isOverdue = false,
      double balanceDue = 100,
    }) => LedgerEntry(
      id: 1,
      customerId: 1,
      customerName: 'C',
      transactionNo: 'T',
      originalAmount: 100,
      balanceDue: balanceDue,
      dueDate: DateTime.parse(date),
      isOverdue: isOverdue,
    );

    test(
      'the server calling it overdue wins, even when the date is in the future',
      () {
        expect(
          due('2026-12-01', isOverdue: true).statusAt(now),
          LedgerStatus.overdue,
          reason:
              'a receivable the server calls overdue must never render as current',
        );
      },
    );

    test('a past due date is overdue even when the server flag is false', () {
      expect(due('2026-10-01').statusAt(now), LedgerStatus.overdue);
    });

    test('within the window is due soon, beyond it is current', () {
      expect(due('2026-10-20').statusAt(now), LedgerStatus.dueSoon);
      expect(due('2026-12-01').statusAt(now), LedgerStatus.current);
    });

    test('zero balance is always paid, even with a past due date', () {
      expect(
        due('2026-10-01', isOverdue: true, balanceDue: 0).statusAt(now),
        LedgerStatus.paid,
      );
    });
  });

  test('parses paid_at on settled ledgers and falls back to recent_payments', () async {
    serve(
      (_) => _json({
        'count': 2,
        'next': null,
        'results': [
          _row(
            id: 10,
            balance: '0.00',
          )..['paid_at'] = '2026-11-15T14:30:00Z',
          {
            ..._row(id: 11, balance: '0.00'),
            'recent_payments': [
              {
                'id': 1,
                'amount_paid': '100.00',
                'payment_method': 'CASH',
                'payment_date': '2026-11-14T08:00:00Z',
              },
              {
                'id': 2,
                'amount_paid': '400.00',
                'payment_method': 'GCASH',
                'payment_date': '2026-11-15T09:15:00Z',
              },
            ],
          },
        ],
      }),
    );

    final entries = await LedgerService(client: client).fetchLedgers();
    expect(entries[0].isPaid, isTrue);
    expect(entries[0].paidAt, DateTime.parse('2026-11-15T14:30:00Z'));
    expect(entries[1].isPaid, isTrue);
    expect(entries[1].paidAt, DateTime.parse('2026-11-15T09:15:00Z'));
  });

  group('payment history pagination and parsing', () {
    Map<String, dynamic> paymentRow({
      required int id,
      required String paymentDate,
      String customerName = 'Reyes Construction',
      String? projectName = 'Tower A',
      String transactionNo = 'TRX-001',
      String amountPaid = '500.00',
      String paymentMethod = 'BANK_TRANSFER',
      String officialReceiptNo = 'BDO-998877',
      String processedByName = 'Store Manager',
      int? paymentReceipt,
      String? cpmsReceiptRef,
    }) => {
      'id': id,
      'collectible': 4,
      'customer_name': customerName,
      'project_name': projectName,
      'transaction_no': transactionNo,
      'processed_by': 2,
      'processed_by_name': processedByName,
      'payment_receipt': paymentReceipt,
      'cpms_receipt_ref': cpmsReceiptRef,
      'amount_paid': amountPaid,
      'payment_method': paymentMethod,
      'payment_date': paymentDate,
      'official_receipt_no': officialReceiptNo,
    };

    test('walks pages, sorts newest first, and identifies CPMS payments', () async {
      serve((options) {
        requestedPages.add('${options.queryParameters['page']}');
        if (options.queryParameters['page'] == 1) {
          return _json({
            'count': 2,
            'next': 'http://x/api/v1/ledger-payments/?page=2',
            'results': [
              paymentRow(
                id: 1,
                paymentDate: '2026-11-14T10:00:00Z',
                projectName: null,
                paymentMethod: 'CASH',
                officialReceiptNo: 'OR-123',
              ),
            ],
          });
        }
        return _json({
          'count': 2,
          'next': null,
          'results': [
            paymentRow(
              id: 2,
              paymentDate: '2026-11-15T16:30:00Z',
              paymentReceipt: 7,
              cpmsReceiptRef: 'BDO-998877',
            ),
          ],
        });
      });

      final payments = await LedgerService(client: client).fetchPayments();
      expect(requestedPages, ['1', '2']);
      expect(payments.map((p) => p.id), [2, 1]);
      expect(payments[0].isFromCpmsReceipt, isTrue);
      expect(payments[0].cpmsReceiptRef, 'BDO-998877');
      expect(payments[0].projectName, 'Tower A');
      expect(payments[1].isFromCpmsReceipt, isFalse);
      expect(payments[1].projectName, isNull);
      expect(payments[1].officialReceiptNo, 'OR-123');
    });
  });

  group('CPMS payment receipts (Phase 1c)', () {
    test('fetches and approves a CPMS online payment receipt', () async {
      serve((options) {
        if (options.path.endsWith('/approve/')) {
          return _json({
            'id': 7,
            'cpms_payment_id': 'PAY-0007',
            'cpms_project_id': 'PRJ-101',
            'project_name': 'Tower A',
            'customer_name': 'Reyes Construction',
            'amount': '1800.00',
            'approved_amount': '1600.00',
            'payment_method': 'BANK_TRANSFER',
            'reference_no': 'BDO-998877',
            'notes': 'Online transfer',
            'submitted_by_name': 'Liza',
            'status': 'APPROVED',
            'decline_reason': '',
            'decided_by_name': 'Store Manager',
            'decided_at': '2026-11-15T12:00:00Z',
            'created_at': '2026-11-15T10:00:00Z',
          });
        }
        return _json({
          'count': 1,
          'next': null,
          'results': [
            {
              'id': 7,
              'cpms_payment_id': 'PAY-0007',
              'cpms_project_id': 'PRJ-101',
              'project_name': 'Tower A',
              'customer_name': 'Reyes Construction',
              'amount': '1800.00',
              'approved_amount': null,
              'payment_method': 'BANK_TRANSFER',
              'reference_no': 'BDO-998877',
              'notes': 'Online transfer',
              'submitted_by_name': 'Liza',
              'status': 'WAITING',
              'decline_reason': '',
              'created_at': '2026-11-15T10:00:00Z',
            },
          ],
        });
      });

      final service = LedgerService(client: client);
      final waiting = await service.fetchPaymentReceipts(status: 'WAITING');
      expect(waiting.single.status, 'WAITING');
      expect(waiting.single.referenceNo, 'BDO-998877');

      final approved = await service.approvePaymentReceipt(
        7,
        approvedAmount: 1600,
      );
      expect(approved.status, 'APPROVED');
      expect(approved.approvedAmount, 1600);
      expect(approved.decidedByName, 'Store Manager');
      expect(approved.decidedAt, DateTime.parse('2026-11-15T12:00:00Z'));
    });
  });
}
