// FX2 (wave 3a fix pass): the categories read must walk EVERY page.
//
// `getList` answers one DRF page (50). K3 renders the category list and the
// product count per card, and the product form picks a category from it, so a
// one-page read hid every category past the fiftieth behind a screen that read
// as the complete catalogue. `fetchPurchaseOrders` and `fetchAdjustments`
// already use `ApiClient.getAll`; this pins the categories to the same walk.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/catalogue_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _categoriesPath = '/api/v1/categories/';

Map<String, dynamic> _category({required int id, required String name}) => {
  'id': id,
  'name': name,
  'is_active': true,
};

/// Answers `page` N of one list endpoint, so a paging walk can be observed.
class _PagedAdapter implements HttpClientAdapter {
  _PagedAdapter(this.pages);

  /// Body per page, in order. Past the end the last page is answered again.
  final List<Map<String, dynamic>> pages;
  final List<String?> requestedPages = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final page = options.queryParameters['page'];
    requestedPages.add(page == null ? null : '$page');
    final index = (page is int ? page : int.tryParse('$page') ?? 1) - 1;
    final body = index >= 0 && index < pages.length ? pages[index] : pages.last;
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient client;
  // `ApiClient.init()` assigns a `late final dio`, so it is NOT idempotent.
  setUpAll(() => client = ApiClient.instance..init());

  CatalogueService service() => CatalogueService(client: client);

  test('fetchCategories reads every page, not only the first', () async {
    final paged = _PagedAdapter([
      {
        'count': 3,
        'next': 'http://test$_categoriesPath?page=2',
        'previous': null,
        'results': [
          _category(id: 1, name: 'Electrical'),
          _category(id: 2, name: 'Plumbing'),
        ],
      },
      {
        'count': 3,
        'next': null,
        'previous': 'http://test$_categoriesPath?page=1',
        'results': [_category(id: 3, name: 'Hardware')],
      },
    ]);
    client.dio.httpClientAdapter = paged;

    final categories = await service().fetchCategories();

    expect(categories.map((category) => category.id).toList(), [1, 2, 3]);
    expect(paged.requestedPages, [
      '1',
      '2',
    ], reason: 'the walk must ask for the second page, not stop at the first');
  });
}
