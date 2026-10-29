import 'package:client/data/models/json_field.dart';

/// A selling unit for a [ProductVariant] — mirrors `GET /api/v1/variant-uoms/`.
///
/// This is the level that owns the price the customer is charged
/// (`defaultSellingPrice`) and the scannable `barcodeQr`.
/// Decision: `planning/api-integration/decisions/08-pricing-rule.md`.
class VariantUom {
  const VariantUom({
    required this.id,
    required this.variantId,
    required this.uomId,
    required this.uomCode,
    required this.uomName,
    required this.barcodeQr,
    required this.conversionFactor,
    required this.defaultSellingPrice,
    this.productName = '',
    this.variantName = '',
    this.productIsActive = true,
    this.variantIsActive = true,
  });

  final int id;
  final int variantId;
  final int uomId;
  final String uomCode;
  final String uomName;

  /// Scannable code — the unit's OWN identity, never a neighbour's.
  ///
  /// The server guarantees a non-blank code on every selling unit (Phase 6
  /// decision 16): a factory EAN, or `QB` + 6-digit id + `-` + check digit.
  /// Still defaulted to empty here, because the nested `selling_uoms` rows on the
  /// products endpoint are read by UI that must not break on an older server.
  final String barcodeQr;

  /// How many base units one of this selling unit contains.
  final double conversionFactor;

  final double defaultSellingPrice;

  /// Names and archive flags, carried by `GET /variant-uoms/?barcode=` so the
  /// till can say WHY a scanned code cannot be sold (decision 13). The nested
  /// products endpoint does not send them, so they default to the sellable state.
  final String productName;
  final String variantName;
  final bool productIsActive;
  final bool variantIsActive;

  /// The one normalisation rule for a code, shared by every writer and reader.
  ///
  /// The server trims and upper-cases before it stores or compares (decision 11),
  /// so a scanner's ` qb000013-0 ` and the stored `QB000013-0` are the same code.
  static String normalise(String code) => code.trim().toUpperCase();

  /// True for a code the server generated itself (`QB…`) — the only kind a label
  /// printer can make a sticker for.
  bool get isInternalCode => barcodeQr.startsWith('QB');

  factory VariantUom.fromJson(Map<String, dynamic> json) {
    return VariantUom(
      id: intField(json, 'id'),
      variantId: intField(json, 'variant'),
      uomId: intField(json, 'uom'),
      uomCode: stringField(json, 'uom_code'),
      uomName: stringField(json, 'uom_name'),
      barcodeQr: stringField(json, 'barcode_qr'),
      conversionFactor: decimalField(json, 'conversion_factor'),
      defaultSellingPrice: decimalField(json, 'default_selling_price'),
      productName: json['product_name'] as String? ?? '',
      variantName: json['variant_name'] as String? ?? '',
      productIsActive: boolFieldOr(json, 'product_is_active', or: true),
      variantIsActive: boolFieldOr(json, 'variant_is_active', or: true),
    );
  }
}
