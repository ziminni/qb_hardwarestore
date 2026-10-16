// The pagination envelope is unwrapped in exactly ONE place (decision 03).
//
// Every POS list endpoint returns {count, next, previous, results} with
// PAGE_SIZE 50. `parsePaged` is a pure function so it can be tested without a
// network; `ApiClient.getList<T>` is the thin call that uses it.
//
// Contract: ENDPOINTS.md §1. Decision: decisions/03-pagination-envelope-strategy.md.

import 'package:client/core/network/paged.dart';
import 'package:flutter_test/flutter_test.dart';

/// A real `/api/v1/categories/` response body, trimmed to two rows.
Map<String, dynamic> envelope({
  List<Map<String, dynamic>>? results,
  int? count,
  bool includeCount = true,
}) {
  final rows =
      results ??
      [
        {'id': 1, 'name': 'Cement'},
        {'id': 2, 'name': 'Electrical'},
      ];
  return {
    if (includeCount) 'count': count ?? rows.length,
    'next': null,
    'previous': null,
    'results': rows,
  };
}

class Category {
  const Category({required this.id, required this.name});
  final int id;
  final String name;
  factory Category.fromJson(Map<String, dynamic> json) =>
      Category(id: json['id'] as int, name: json['name'] as String);
}

void main() {
  group('parsePaged', () {
    test('unwraps the results list and the count', () {
      final page = parsePaged<Category>(envelope(), Category.fromJson);

      expect(page.items, hasLength(2));
      expect(page.items.first.id, 1);
      expect(page.items.first.name, 'Cement');
      expect(page.items.last.name, 'Electrical');
      expect(page.total, 2);
    });

    test('a full page reports a total larger than the items it carries', () {
      // The realistic shape: count is the WHOLE collection, results is one page.
      final page = parsePaged<Category>(
        envelope(
          results: [
            {'id': 1, 'name': 'Cement'},
          ],
          count: 137,
        ),
        Category.fromJson,
      );

      expect(page.items, hasLength(1));
      expect(page.total, 137);
    });

    test('an empty collection is an empty page, not an error', () {
      final page = parsePaged<Category>(
        envelope(results: const [], count: 0),
        Category.fromJson,
      );

      expect(page.items, isEmpty);
      expect(page.total, 0);
    });

    test('the returned items list cannot be mutated by callers', () {
      final page = parsePaged<Category>(envelope(), Category.fromJson);

      expect(
        () => page.items.add(Category.fromJson({'id': 3, 'name': 'x'})),
        throwsUnsupportedError,
      );
    });

    test('throws when the body is not the envelope map at all', () {
      expect(
        () => parsePaged<Category>(const [1, 2, 3], Category.fromJson),
        throwsFormatException,
      );
    });

    test('throws when the envelope has no results key', () {
      // A bare `get` against a list endpoint returns exactly this.
      expect(
        () => parsePaged<Category>(const {'count': 2}, Category.fromJson),
        throwsFormatException,
      );
    });

    test('throws when results is not a list', () {
      expect(
        () => parsePaged<Category>(const {
          'count': 1,
          'results': 'nope',
        }, Category.fromJson),
        throwsFormatException,
      );
    });

    test('throws when count is missing', () {
      // Fail loudly rather than silently reporting total = items.length, which
      // would make a paged list look complete.
      expect(
        () => parsePaged<Category>(
          envelope(includeCount: false),
          Category.fromJson,
        ),
        throwsFormatException,
      );
    });

    test('throws when a row is not a JSON object', () {
      expect(
        () => parsePaged<Category>(const {
          'count': 1,
          'results': ['not-an-object'],
        }, Category.fromJson),
        throwsFormatException,
      );
    });

    test('propagates a row parse failure rather than skipping the row', () {
      // A malformed row must not be dropped: dropping it would silently shorten
      // a list the user is counting on.
      expect(
        () => parsePaged<Category>(
          envelope(
            results: [
              {'id': 1, 'name': 'Cement'},
              {'id': 2}, // no name
            ],
          ),
          Category.fromJson,
        ),
        throwsA(isA<TypeError>()),
      );
    });
    test('hasMore is false when the page holds the whole collection', () {
      final single = parsePaged<Category>(
        envelope(
          results: [
            {'id': 1, 'name': 'Cement'},
          ],
          count: 1,
        ),
        Category.fromJson,
      );
      final firstOfMany = parsePaged<Category>(
        envelope(
          results: [
            {'id': 1, 'name': 'Cement'},
          ],
          count: 2,
        ),
        Category.fromJson,
      );

      expect(single.hasMore, isFalse);
      expect(firstOfMany.hasMore, isTrue);
    });

    test('ignores the envelope keys it does not need', () {
      // `next`/`previous` are null or URLs depending on the page, and paging is
      // deferred because no seeded list exceeds PAGE_SIZE. They must not be able
      // to break parsing of a page that is otherwise fine.
      final page = parsePaged<Category>({
        'count': 2,
        'next': 'http://example.test/api/v1/categories/?page=2',
        'previous': 'http://example.test/api/v1/categories/?page=0',
        'results': [
          {'id': 1, 'name': 'Cement'},
          {'id': 2, 'name': 'Electrical'},
        ],
      }, Category.fromJson);

      expect(page.items, hasLength(2));
      expect(page.total, 2);
    });
  });
}
