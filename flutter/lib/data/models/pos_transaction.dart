class PosCartLine {
  const PosCartLine({
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
  });

  final String productName;
  final double quantity;
  final String unit;
  final double unitPrice;

  double get total => quantity * unitPrice;

  PosCartLine copyWith({double? quantity}) => PosCartLine(
    productName: productName,
    quantity: quantity ?? this.quantity,
    unit: unit,
    unitPrice: unitPrice,
  );
}

class PosReceipt {
  const PosReceipt({
    required this.reference,
    required this.createdAt,
    required this.lines,
    required this.paymentMethod,
    required this.amountPaid,
    required this.total,
  });

  final String reference;
  final DateTime createdAt;
  final List<PosCartLine> lines;
  final String paymentMethod;
  final double amountPaid;
  final double total;

  double get change => amountPaid - total;
}
