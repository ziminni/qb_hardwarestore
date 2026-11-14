import 'package:client/core/format/format.dart';
import 'package:client/data/models/json_field.dart';

/// One shelf a line was picked from: `pick_up` on a sale line, a delivery-slip
/// item and a release line (Phase 9, decision 21 §2 and §4).
///
/// The server groups a line's `SalesItemDeduction` rows by location, in the order
/// its allocator took them (home first, then the other shelves), so this list
/// reads the way a picker walks. `qty` is in [unit] — the line's selling unit
/// when every part divides exactly, otherwise base units — because "0.58 BOX" is
/// not something anybody can count off a shelf.
class PickUpPart {
  const PickUpPart({
    required this.locationId,
    required this.locationName,
    required this.qty,
    required this.unit,
  });

  final int locationId;
  final String locationName;
  final double qty;
  final String unit;

  factory PickUpPart.fromJson(Map<String, dynamic> json) => PickUpPart(
    locationId: intField(json, 'location'),
    locationName: stringField(json, 'location_name'),
    qty: decimalField(json, 'qty'),
    unit: stringField(json, 'unit'),
  );
}

/// The pick-up caption for ONE line, or null when there is nothing to print.
///
/// A line with parts says where each part left — `Pick up: 3 PC at Store, 2 PC at
/// Bodega` — which is the fact the picker and the driver need. A line with NO
/// parts was sold before Phase 9 or has not been fulfilled yet, so it keeps the
/// caption Phase 5 printed from the product's `stored_at`: `Pick up at Bodega`.
/// Neither one present means NO caption: an invented "Store" would send somebody
/// to collect goods from a place nobody chose.
///
/// The wording lives here, in one place, so the receipt, the on-screen receipt,
/// the delivery slip and the release receipt cannot drift apart.
String? pickUpCaption({
  required List<PickUpPart> pickUp,
  required String storedAtName,
}) {
  if (pickUp.isEmpty) {
    final fallback = storedAtName.trim();
    return fallback.isEmpty ? null : 'Pick up at $fallback';
  }
  final parts = pickUp
      .map((part) => '${formatQuantity(part.qty)} ${part.unit} at '
          '${part.locationName}'.trim().replaceAll('  ', ' '))
      .join(', ');
  return 'Pick up: $parts';
}
