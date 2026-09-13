enum StockAdjustmentType {
  shrinkage('SHRINKAGE', 'Shrinkage / Loss'),
  damage('DAMAGE', 'Damaged'),
  correction('CORRECTION', 'Count Correction'),
  returnToSupplier('RETURN', 'Return to Supplier');

  const StockAdjustmentType(this.apiValue, this.displayName);

  final String apiValue;
  final String displayName;

  static StockAdjustmentType fromApiValue(String value) {
    return values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () => StockAdjustmentType.correction,
    );
  }
}

class StockAdjustment {
  const StockAdjustment({
    required this.id,
    required this.variantId,
    required this.userId,
    required this.adjustmentType,
    required this.quantityAdjusted,
    required this.remarks,
    required this.timestamp,
  });

  final int id;
  final int variantId;
  final int userId;
  final StockAdjustmentType adjustmentType;
  final double quantityAdjusted;
  final String remarks;
  final DateTime timestamp;

  factory StockAdjustment.fromJson(Map<String, dynamic> json) {
    return StockAdjustment(
      id: json['id'] as int,
      variantId: json['variant'] as int,
      userId: json['user'] as int,
      adjustmentType: StockAdjustmentType.fromApiValue(
        json['adjustment_type'] as String,
      ),
      quantityAdjusted: double.parse(json['qty_adjusted'].toString()),
      remarks: json['remarks'] as String? ?? '',
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

enum InventoryMovementType {
  initialStock('Initial Stock'),
  purchaseReceipt('Purchase Receipt'),
  sale('Sale'),
  stockAdjustment('Stock Adjustment'),
  customerReturn('Customer Return'),
  supplierReturn('Supplier Return');

  const InventoryMovementType(this.label);
  final String label;
}

enum InventoryStockStatus {
  inStock('In Stock'),
  lowStock('Low Stock'),
  outOfStock('Out of Stock');

  const InventoryStockStatus(this.label);
  final String label;
}

class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.timestamp,
    required this.productId,
    required this.variantId,
    required this.type,
    required this.quantityChange,
    required this.previousStock,
    required this.newStock,
    required this.reference,
    required this.reason,
    required this.userName,
  });

  final int id;
  final DateTime timestamp;
  final int productId;
  final int variantId;
  final InventoryMovementType type;
  final double quantityChange;
  final double previousStock;
  final double newStock;
  final String reference;
  final String reason;
  final String userName;
}
