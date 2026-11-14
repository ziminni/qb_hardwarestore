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
    this.uomIsWhole = false,
    this.storedAtId,
    this.storedAtName = '',
    this.inUse = false,
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

  /// The SERVER's whole-number flag for this unit (Phase 1d).
  ///
  /// It replaces the client's own list of whole unit words, because the flag is
  /// what the server enforces: a shop that flags `PC` as measured, or that sells
  /// a `QABUNDLE` in ones, is answered correctly by reading the field. A row from
  /// an older server omits it, and "measured" is the safe reading — the till then
  /// asks for the quantity instead of adding a count it cannot take back.
  final bool uomIsWhole;

  /// True when a sale, held cart, return, quotation, sales order or project
  /// request line already references this unit, so it cannot be removed.
  final bool inUse;

  /// Where the unit's PRODUCT is kept (Phase 5 B4, decision 18), so the till can
  /// badge a scanned line without holding the product list. Null/empty when the
  /// server did not send it.
  final int? storedAtId;
  final String storedAtName;

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
      uomIsWhole: boolFieldOr(json, 'uom_is_whole', or: false),
      storedAtId: json['stored_at'] is int ? json['stored_at'] as int : null,
      storedAtName: json['stored_at_name'] is String
          ? json['stored_at_name'] as String
          : '',
      inUse: boolFieldOr(json, 'in_use', or: false),
    );
  }
}
