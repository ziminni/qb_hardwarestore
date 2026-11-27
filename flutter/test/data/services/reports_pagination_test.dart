import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter({this.incomplete = false});
  final bool incomplete;
  final pages = <int>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final page = (options.queryParameters['page'] as int?) ?? 1;
    pages.add(page);
    final body = {
      'from': '2026-10-01',
      'to': '2026-10-31',
      'totals': {'transactions': 2, 'invoice_total': '100.00'},
      'count': 2,
      'next': page == 1 && !incomplete ? 'next-page' : null,
      'results': [
        {'hour': page, 'transactions': 1, 'invoice_total': '50.00'},
      ],
    };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUpAll(() => ApiClient.instance.init());
  test(
    'the service joins all report pages and keeps full-range totals',
    () async {
      final adapter = _Adapter();
      ApiClient.instance.dio.httpClientAdapter = adapter;
      final report = await ReportsService().fetchSalesByHour(
        from: '2026-10-01',
        to: '2026-10-31',
      );
      expect(adapter.pages, [1, 2]);
      expect(report.page.rows.map((row) => row.hour), [1, 2]);
      expect(report.totalInvoice, 100);
    },
  );
  test(
    'an incomplete range is rejected instead of silently exported',
    () async {
      ApiClient.instance.dio.httpClientAdapter = _Adapter(incomplete: true);
      await expectLater(
        ReportsService().fetchSalesByHour(),
        throwsA(isA<ReportsServiceException>()),
      );
    },
  );
}
