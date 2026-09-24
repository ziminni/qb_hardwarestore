class PosCatalogItem {
  const PosCatalogItem({required this.variantUomId, required this.variantId, required this.productName, required this.variantName, required this.unit, required this.barcode, required this.conversionFactor, required this.unitPrice, required this.availableBaseStock});
  final int variantUomId;
  final int variantId;
  final String productName;
  final String variantName;
  final String unit;
  final String barcode;
  final double conversionFactor;
  final double unitPrice;
  final double availableBaseStock;
  double get availableSaleQuantity => availableBaseStock / conversionFactor;
}

class PosCustomer {
  const PosCustomer({required this.id, required this.name, required this.type});
  final int id;
  final String name;
  final String type;
  factory PosCustomer.fromJson(Map<String, dynamic> json) => PosCustomer(id: json['id'] as int, name: json['name'] as String, type: json['customer_type'] as String? ?? 'WALK_IN');
}

class PosCartLine {
  const PosCartLine({required this.variantUomId, required this.productName, required this.variantName, required this.quantity, required this.unit, required this.unitPrice, required this.availableQuantity});
  final int variantUomId;
  final String productName;
  final String variantName;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double availableQuantity;
  double get total => quantity * unitPrice;
  PosCartLine copyWith({double? quantity}) => PosCartLine(variantUomId: variantUomId, productName: productName, variantName: variantName, quantity: quantity ?? this.quantity, unit: unit, unitPrice: unitPrice, availableQuantity: availableQuantity);
  Map<String, dynamic> toCheckoutJson() => {'variant_id': variantUomId, 'qty': quantity, 'unit_price': unitPrice};
}

class PosReceipt {
  const PosReceipt({required this.reference, required this.officialReceiptNumber, required this.createdAt, required this.lines, required this.paymentMethod, required this.amountPaid, required this.total});
  final String reference;
  final String officialReceiptNumber;
  final DateTime createdAt;
  final List<PosCartLine> lines;
  final String paymentMethod;
  final double amountPaid;
  final double total;
  double get change => amountPaid - total;
}

class PosCheckoutResult {
  const PosCheckoutResult({required this.transactionNumber, required this.officialReceiptNumber, required this.createdAt, required this.total});
  final String transactionNumber;
  final String officialReceiptNumber;
  final DateTime createdAt;
  final double total;
}
