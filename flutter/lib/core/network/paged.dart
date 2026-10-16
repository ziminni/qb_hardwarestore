/// Pagination for every DRF list endpoint.
///
/// The POS API returns the standard envelope on every list route:
///
/// ```json
/// { "count": 137, "next": "...", "previous": null, "results": [ ... ] }
/// ```
///
/// Decision 03 locked the rule that this envelope is unwrapped in **exactly one
/// place** — here — rather than in each of the 27 screens or each repository.
/// `count` is the size of the whole collection, not of the page that arrived.
///
/// Contract: `ENDPOINTS.md` §1. Decision:
/// `planning/api-integration/decisions/03-pagination-envelope-strategy.md`.
library;

/// One page of a list response.
class Paged<T> {
  Paged({required List<T> items, required this.total})
    : items = List.unmodifiable(items);

  /// The rows on this page.
  final List<T> items;

  /// The size of the **whole** collection, not of [items]. A list of 50 rows
  /// with `total` 137 is a full first page, not a complete list.
  final int total;

  bool get isEmpty => items.isEmpty;
  int get length => items.length;

  /// True when the collection is larger than the page that arrived.
  bool get hasMore => total > items.length;
}

/// Unwraps the `{count, next, previous, results}` envelope into a [Paged].
///
/// Pure, so it is testable without a network, and strict, so a malformed
/// response fails loudly instead of rendering an empty list. A missing `count`
/// is an error rather than a default of `items.length`: silently reporting the
/// page size as the total would make a paginated list look complete.
///
/// [fromJson] is the row model's own factory; a failure inside it propagates
/// rather than dropping the row, because dropping a row would silently shorten
/// a list the user is counting on.
Paged<T> parsePaged<T>(
  dynamic body,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (body is! Map<String, dynamic>) {
    throw FormatException(
      'Expected a paginated envelope object but got ${body.runtimeType}.',
    );
  }

  final results = body['results'];
  if (results is! List) {
    throw const FormatException(
      'Paginated envelope has no "results" list. '
      'Only list endpoints are paginated — check the path.',
    );
  }

  final count = body['count'];
  if (count is! num) {
    throw const FormatException(
      'Paginated envelope has no numeric "count".',
    );
  }

  final items = <T>[];
  for (final row in results) {
    if (row is! Map<String, dynamic>) {
      throw FormatException(
        'Paginated envelope contains a ${row.runtimeType} row; '
        'expected an object.',
      );
    }
    items.add(fromJson(row));
  }

  return Paged<T>(items: items, total: count.toInt());
}
