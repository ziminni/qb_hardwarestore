import 'package:client/data/models/json_field.dart';

/// How much of one variant sits on ONE shelf — mirrors one row of
/// `GET /api/v1/stock-on-hand/`.
///
/// Phase 9 F1 (decision 21 §5): the server answers this, grouped per
/// (variant, location). Before it, every screen summed `GET /api/v1/batches/`
/// itself, which is a whole-shop total that cannot say where the goods are.
/// Quantity therefore comes from here; `/batches/` stays for COST (the newest
/// batch's landed cost, decision 08) and for the valuation dashboards.
///
/// `qty` is base units, like every stock figure. A variant with no live stock
/// has no row at all — an exhausted batch adds no `0.00`.
class StockOnHand {
  const StockOnHand({
    required this.variantId,
    required this.locationId,
    required this.locationName,
    required this.locationActive,
    required this.isHome,
    required this.qty,
  });

  final int variantId;
  final int locationId;

  /// The shelf's name, as the server spells it ("Store", "Bodega").
  final String locationName;

  /// False for a deactivated shelf: its stock is still sellable (owner ruling,
  /// taken last), it just cannot receive or be a transfer destination.
  final bool locationActive;

  /// True when this is the variant's PRODUCT `stored_at` — its home shelf, which
  /// the server's allocator takes first.
  final bool isHome;

  /// Quantity at this location, in the variant's base unit.
  final double qty;

  factory StockOnHand.fromJson(Map<String, dynamic> json) {
    return StockOnHand(
      variantId: intField(json, 'variant'),
      locationId: intField(json, 'location'),
      locationName: stringField(json, 'location_name'),
      locationActive: boolFieldOr(json, 'location_active', or: true),
      isHome: boolFieldOr(json, 'is_home', or: false),
      qty: decimalField(json, 'qty'),
    );
  }
}
