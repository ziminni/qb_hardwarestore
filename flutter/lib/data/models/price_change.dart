import 'package:client/data/models/json_field.dart';

/// One store-wide selling-unit price change row from `GET /api/v1/price-changes/`.
class StorePriceChange {
  const StorePriceChange({
    required this.id,
    required this.variantUomId,
    required this.productId,
    required this.productName,
    required this.variantName,
    required this.unitCode,
    required this.barcodeQr,
    required this.oldPrice,
    required this.newPrice,
    required this.changeAmount,
    required this.changePercent,
    required this.changedAt,
    required this.changedByName,
    required this.source,
  });

  final int id;
  final int variantUomId;
  final int productId;
  final String productName;
  final String variantName;
  final String unitCode;
  final String barcodeQr;
  final double? oldPrice;
  final double newPrice;
  final double? changeAmount;
  final double? changePercent;
  final DateTime? changedAt;
  final String? changedByName;
  final String source;

  factory StorePriceChange.fromJson(Map<String, dynamic> json) {
    double? optDecimal(String key) {
      final raw = json[key];
      if (raw == null) return null;
      if (raw is num) return raw.toDouble();
      if (raw is String) return double.tryParse(raw);
      return null;
    }

    return StorePriceChange(
      id: intField(json, 'id'),
      variantUomId: intField(json, 'variant_uom'),
      productId: json['product_id'] is int ? json['product_id'] as int : 0,
      productName: json['product_name'] as String? ?? '',
      variantName: json['variant_name'] as String? ?? '',
      unitCode: json['unit_code'] as String? ?? '',
      barcodeQr: json['barcode_qr'] as String? ?? '',
      oldPrice: optDecimal('old_price'),
      newPrice: decimalField(json, 'new_price'),
      changeAmount: optDecimal('change_amount'),
      changePercent: optDecimal('change_percent'),
      changedAt: json['changed_at'] is String
          ? DateTime.tryParse(json['changed_at'] as String)
          : null,
      changedByName: json['changed_by_name'] as String?,
      source: (json['source'] as String? ?? '').toUpperCase(),
    );
  }
}
