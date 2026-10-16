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
  });

  final int id;
  final int variantId;
  final int uomId;
  final String uomCode;
  final String uomName;

  /// Scannable code. Empty (`''`) in the seeded data, so the UI must not
  /// assume a barcode exists.
  final String barcodeQr;

  /// How many base units one of this selling unit contains.
  final double conversionFactor;

  final double defaultSellingPrice;

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
    );
  }
}
