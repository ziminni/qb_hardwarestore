// Phase 4 task 3 (decision 14). The POS must select AND create customers mid-sale, and show
// a customer's utang at the till. That needs a service, a pass-through repository, and a
// Customer model that knows all FOUR types.
//
// Four types, not three: the stub for decision 14 listed WALK_IN/REGULAR/CONTRACTOR, but the
// model and the migration also carry CONSTRUCTION_FIRM, and seed_demo uses it. A picker built
// from the stub's list would mislabel every firm customer.
//
// The ledger summary comes from `/api/v1/ledgers/aging/` rather than the per-customer list:
// aging already returns one group per customer with `total_balance`, `open_count` and
// `overdue_count` - exactly the panel's line items - so the balance needs no client-side sum
// and no second call.

import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/repositories/customer_repository.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the request and replays a canned body.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, {this.statusCode = 200});

  final Object body;
  int statusCode;
  RequestOptions? lastRequest;

  /// The adapter this one replaced, kept so tearDown can put it back — Dio's
  /// `httpClientAdapter` is non-nullable, so it can never be nulled to reset it, and
  /// leaving the fake installed leaks it into every later test in the process.
  HttpClientAdapter? replaced;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _page(List<Map<String, dynamic>> rows) => {
  'count': rows.length,
  'next': null,
  'previous': null,
  'results': rows,
};

void main() {
  _paginationTests();

  late ApiClient client;
  late CustomerService service;
  // Nullable because not every test installs one: a test that serves its own multi-page
  // adapter leaves this unset, and a `late` field would throw in the shared tearDown.
  _FakeAdapter? adapter;

  setUpAll(() {
    // The house pattern, and load-bearing: `ApiClient.init()` is NOT idempotent (dio is
    // `late final`), so it must run exactly once or every test dies with LateInitializationError.
    client = ApiClient.instance..init();
  });

  setUp(() {
    service = CustomerService(client: client);
  });

  tearDown(() {
    final previous = adapter?.replaced;
    if (previous != null) client.dio.httpClientAdapter = previous;
  });

  void serve(Object body, {int status = 200}) {
    final fake = _FakeAdapter(body, statusCode: status)
      ..replaced = client.dio.httpClientAdapter;
    adapter = fake;
    client.dio.httpClientAdapter = fake;
  }

  test('lists customers and parses all four types', () async {
    serve(
      _page([
        {'id': 1, 'name': 'Walk-in Customer', 'customer_type': 'WALK_IN'},
        {'id': 2, 'name': 'Maria Santos', 'customer_type': 'REGULAR'},
        {
          'id': 3,
          'name': 'Dela Cruz Construction',
          'customer_type': 'CONSTRUCTION_FIRM',
        },
        {'id': 4, 'name': 'Pedro Contractor', 'customer_type': 'CONTRACTOR'},
      ]),
    );

    final customers = await service.fetchCustomers();

    expect(customers, hasLength(4));
    expect(customers[0].type, CustomerType.walkIn);
    expect(customers[1].type, CustomerType.regular);
    expect(
      customers[2].type,
      CustomerType.constructionFirm,
      reason: 'the fourth type exists in the model and the migration',
    );
    expect(customers[3].type, CustomerType.contractor);
  });

  test(
    'an unrecognised type does not throw - it must not shorten the picker',
    () async {
      serve(
        _page([
          {'id': 9, 'name': 'Future Type Co', 'customer_type': 'FRANCHISE'},
        ]),
      );

      final customers = await service.fetchCustomers();

      expect(customers.single.type, CustomerType.unknown);
      expect(customers.single.name, 'Future Type Co');
    },
  );

  test(
    'creates a customer with the minimal record and no credit limit',
    () async {
      serve({
        'id': 7,
        'name': 'Nena Reyes',
        'customer_type': 'REGULAR',
      }, status: 201);

      final created = await service.createCustomer(
        name: 'Nena Reyes',
        type: CustomerType.regular,
      );

      expect(created.id, 7);
      expect(created.name, 'Nena Reyes');
      final sent = adapter!.lastRequest!.data as Map<String, dynamic>;
      expect(sent['name'], 'Nena Reyes');
      expect(sent['customer_type'], 'REGULAR');
      // Locked decision 1: name + type ONLY. Sending a credit limit would put credit control
      // in the cashier's hands at the till.
      expect(
        sent.containsKey('total_credit_limit'),
        isFalse,
        reason: 'the counter form captures name and type, nothing else',
      );
    },
  );

  test('reads one customer\'s utang from the aging report', () async {
    serve({
      'total_customers': 2,
      'total_outstanding': 5372.0,
      'groups': [
        {
          'customer_id': 2,
          'customer_name': 'Maria Santos',
          'total_balance': 4900.0,
          'open_count': 1,
          'overdue_count': 1,
          'entries': [],
        },
        {
          'customer_id': 3,
          'customer_name': 'Dela Cruz Construction',
          'total_balance': 472.0,
          'open_count': 1,
          'overdue_count': 0,
          'entries': [],
        },
      ],
    });

    final summary = await service.fetchLedgerSummary(2);

    expect(summary.customerName, 'Maria Santos');
    expect(summary.totalBalance, 4900.0);
    expect(summary.openCount, 1);
    expect(summary.overdueCount, 1);
    expect(
      summary.hasDebt,
      isTrue,
      reason:
          'the panel shows a balance; an empty one must read as zero, not unknown',
    );
  });

  test('a customer with no ledgers is a ZERO summary, not an error', () async {
    // The aging report only lists customers who have OPEN/PARTIAL/OVERDUE entries, so a
    // customer with no debt is simply absent. Treating that as a failure would make the
    // panel show an error for the commonest case at the till.
    serve({'total_customers': 0, 'total_outstanding': 0, 'groups': []});

    final summary = await service.fetchLedgerSummary(42);

    expect(summary.customerId, 42);
    expect(summary.totalBalance, 0);
    expect(summary.openCount, 0);
    expect(summary.overdueCount, 0);
    expect(summary.hasDebt, isFalse);
  });

  test('a connection failure becomes a CustomerServiceException', () async {
    serve(const {}, status: 500);

    expect(
      () => service.fetchCustomers(),
      throwsA(isA<CustomerServiceException>()),
    );
  });

  test('the repository is a pass-through, holding no policy', () async {
    serve(
      _page([
        {'id': 1, 'name': 'Walk-in Customer', 'customer_type': 'WALK_IN'},
      ]),
    );

    final repository = CustomerRepository(service);
    final customers = await repository.fetchCustomers();

    expect(customers.single.name, 'Walk-in Customer');
  });
}

/// Replays one canned body per call, so a test can serve several PAGES.
class _PagedAdapter implements HttpClientAdapter {
  _PagedAdapter(this.pages);

  final List<Object> pages;
  final List<String?> requestedPages = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPages.add(options.queryParameters['page']?.toString());
    final index = (requestedPages.length - 1).clamp(0, pages.length - 1);
    return ResponseBody.fromString(
      jsonEncode(pages[index]),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// Review finding F4. The picker's search filters the list the client LOADED, and the list was
// one page of 50 - so past 50 customers an existing account silently could not be selected and
// a duplicate record at the till was the likely outcome. The demo database holds three
// customers, which is why no test could see it.
void _paginationTests() {
  late ApiClient client;
  late CustomerService service;
  late _PagedAdapter paged;
  late HttpClientAdapter original;

  setUp(() {
    // NOT `..init()`: init() is not idempotent (dio is `late final`), so calling it again
    // here would rebuild dio and discard the fake adapter every other test installed.
    client = ApiClient.instance;
    service = CustomerService(client: client);
    original = client.dio.httpClientAdapter;
  });

  tearDown(() => client.dio.httpClientAdapter = original);

  test('follows the next link so a customer past page one is findable', () async {
    paged = _PagedAdapter([
      {
        'count': 2,
        'next': 'http://x/api/v1/customers/?page=2',
        'previous': null,
        'results': [
          {'id': 1, 'name': 'Aaa Trading', 'customer_type': 'REGULAR'},
        ],
      },
      {
        'count': 2,
        'next': null,
        'previous': null,
        'results': [
          {'id': 2, 'name': 'Zulu Hardware', 'customer_type': 'CONTRACTOR'},
        ],
      },
    ]);
    client.dio.httpClientAdapter = paged;

    final customers = await service.fetchCustomers();

    expect(
      customers.map((c) => c.name),
      ['Aaa Trading', 'Zulu Hardware'],
      reason: 'a one-page cap hides every customer past 50',
    );
    expect(paged.requestedPages, hasLength(2), reason: 'both pages fetched');
  });

  test('stops at the last page', () async {
    paged = _PagedAdapter([
      {
        'count': 1,
        'next': null,
        'previous': null,
        'results': [
          {'id': 1, 'name': 'Only One', 'customer_type': 'REGULAR'},
        ],
      },
    ]);
    client.dio.httpClientAdapter = paged;

    final customers = await service.fetchCustomers();

    expect(customers, hasLength(1));
    expect(paged.requestedPages, hasLength(1), reason: 'no pointless second request');
  });

  test('a runaway next link is refused rather than looping forever', () async {
    paged = _PagedAdapter([
      {
        'count': 1,
        'next': 'http://x/api/v1/customers/?page=2',
        'previous': null,
        'results': [
          {'id': 1, 'name': 'A', 'customer_type': 'REGULAR'},
        ],
      },
    ]);
    client.dio.httpClientAdapter = paged;

    await expectLater(
      service.fetchCustomers(),
      throwsA(isA<CustomerServiceException>()),
      reason: 'an endless next link must fail loudly, not hang the till',
    );
  });
}
