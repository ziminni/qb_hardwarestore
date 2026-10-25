import 'package:client/data/models/json_field.dart';

/// A brand — `GET /api/v1/brands/`. `{id, name}` and nothing else.
///
/// The product form needs a `brand` id to create a product, so the picker reads
/// the real list. It used to be derived from the brands already used by loaded
/// products, which meant a store with no products could not create its first one.
class Brand {
  const Brand({required this.id, required this.name});

  final int id;
  final String name;

  factory Brand.fromJson(Map<String, dynamic> json) {
    return Brand(id: intField(json, 'id'), name: stringField(json, 'name'));
  }
}

/// A unit of measure — `GET /api/v1/uoms/`. `{id, code, name}`.
///
/// A variant's `base_uom` is set at creation and frozen afterwards, so the form
/// must offer the server's units rather than a hardcoded list of words.
class UnitOfMeasure {
  const UnitOfMeasure({
    required this.id,
    required this.code,
    required this.name,
  });

  final int id;
  final String code;
  final String name;

  /// What a picker shows: `Kilogram (KG)`.
  String get label => '$name ($code)';

  factory UnitOfMeasure.fromJson(Map<String, dynamic> json) {
    return UnitOfMeasure(
      id: intField(json, 'id'),
      code: stringField(json, 'code'),
      name: stringField(json, 'name'),
    );
  }
}
