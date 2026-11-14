import 'package:client/data/models/json_field.dart';

/// A product category — `GET /api/v1/categories/` (Phase 4 Task 1).
///
/// The server carries exactly `id`, `name` and `is_active`; there is no
/// description column, so this model has none. It used to hold one, right up to
/// Phase 4, because the mock catalogue invented descriptions the API could never
/// have returned — which is why the categories screen could not go live without
/// this change: every row would have shown an empty paragraph that looked like
/// missing data.
class Category {
  const Category({required this.id, required this.name, this.isActive = true});

  final int id;
  final String name;

  /// False once archived. Archiving is the supported exit — the route answers
  /// **405** to DELETE — and the products filed under it stay sellable.
  final bool isActive;

  Category copyWith({String? name, bool? isActive}) {
    return Category(
      id: id,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
    );
  }

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: intField(json, 'id'),
      name: stringField(json, 'name'),
      isActive: boolFieldOr(json, 'is_active', or: true),
    );
  }
}
