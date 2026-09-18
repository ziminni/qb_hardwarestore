enum InventorySaleStatus {
  completed('Completed'),
  voided('Void'),
  refunded('Refunded');

  const InventorySaleStatus(this.label);
  final String label;
}

enum InventoryReturnType {
  customer('Customer Return'),
  supplier('Supplier Return');

  const InventoryReturnType(this.label);
  final String label;
}

enum InventoryReturnStatus {
  pending('Pending'),
  approved('Approved'),
  completed('Completed'),
  rejected('Rejected');

  const InventoryReturnStatus(this.label);
  final String label;
}

class InventorySaleLine {
  const InventorySaleLine({
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.quantity,
    required this.unitPrice,
  });
  final String productName;
  final String variantName;
  final String sku;
  final double quantity;
  final double unitPrice;
  double get subtotal => quantity * unitPrice;
}

class InventorySale {
  const InventorySale({
    required this.transactionNo,
    required this.date,
    required this.customer,
    required this.cashier,
    required this.paymentMethod,
    required this.source,
    required this.status,
    required this.lines,
  });
  final String transactionNo;
  final DateTime date;
  final String customer;
  final String cashier;
  final String paymentMethod;
  final String source;
  final InventorySaleStatus status;
  final List<InventorySaleLine> lines;
  double get total => lines.fold(0, (sum, line) => sum + line.subtotal);
  double get totalQuantity => lines.fold(0, (sum, line) => sum + line.quantity);
}

class InventoryReturn {
  const InventoryReturn({
    required this.reference,
    required this.date,
    required this.type,
    required this.relatedReference,
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.quantity,
    required this.reason,
    required this.status,
    required this.processedBy,
  });
  final String reference;
  final DateTime date;
  final InventoryReturnType type;
  final String relatedReference;
  final String productName;
  final String variantName;
  final String sku;
  final double quantity;
  final String reason;
  final InventoryReturnStatus status;
  final String processedBy;
}
