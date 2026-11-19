import 'package:client/data/models/catalogue_option.dart';

/// How a product is measured, as the Add product chips name it (adopted from
/// the teammate's `ui/frontend-progress` form, owner 2026-11-18).
///
/// It is a way of PICKING the base unit, not a field of its own: the server
/// stores the unit, and the unit alone decides whether fractions are allowed
/// (`UnitOfMeasure.isWhole`). The kind is read back from the unit's code.
enum TrackingKind {
  quantity('By Quantity', 'Items counted individually'),
  weight('By Weight', 'Sold by kilogram or gram'),
  length('By Length', 'Sold by metre or centimetre'),
  volume('By Volume', 'Sold by litre or cubic metre');

  const TrackingKind(this.label, this.caption);

  final String label;
  final String caption;

  static const _weight = {'KG', 'G', 'MG', 'LB', 'TON', 'T'};
  static const _length = {'M', 'CM', 'MM', 'KM', 'FT', 'IN', 'YD', 'LM'};
  static const _volume = {'L', 'ML', 'CU.M', 'CUM', 'M3', 'GAL', 'CU.FT'};

  /// The kind a unit belongs to; anything not measured is counted.
  static TrackingKind of(UnitOfMeasure unit) {
    final code = unit.code.trim().toUpperCase();
    if (_weight.contains(code)) return TrackingKind.weight;
    if (_length.contains(code)) return TrackingKind.length;
    if (_volume.contains(code)) return TrackingKind.volume;
    return TrackingKind.quantity;
  }

  /// [units] of this kind, in the order the server listed them.
  List<UnitOfMeasure> unitsIn(List<UnitOfMeasure> units) => [
    for (final unit in units)
      if (TrackingKind.of(unit) == this) unit,
  ];
}
