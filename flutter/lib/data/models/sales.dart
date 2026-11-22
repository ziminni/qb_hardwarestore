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
    required this.variantUomId,
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.quantity,
    required this.unitPrice,
  });

  /// The selling unit's id. The only field the wire sends that identifies WHICH
  /// product was sold: names must be resolved against the catalogue.
  final int variantUomId;
  final String productName;
  final String variantName;
  final String sku;
  final double quantity;
  final double unitPrice;
  double get subtotal => quantity * unitPrice;
}

/// One payment against a sale: the method and what was tendered.
///
/// Mirrors `pos.serializers.TransactionPaymentSerializer` as the View sheet
/// (decision D-02) needs it: how it was paid, and how much.
class InventorySalePayment {
  const InventorySalePayment({
    required this.method,
    required this.amount,
    this.fee = 0,
  });
  final String method;
  final double amount;
  final double fee;
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
    this.payments = const [],
    this.discountAmount = 0,
    this.discountReason = '',
    this.vatableSales = 0,
    this.vatAmount = 0,
    this.vatRegistered = true,
    this.paymentFee = 0,
    this.creditSale = false,
    this.bodegaStatus,
    this.orNumber = '',
  });
  final String transactionNo;
  final DateTime date;
  final String customer;
  final String cashier;
  final String paymentMethod;
  final String source;
  final InventorySaleStatus status;
  final List<InventorySaleLine> lines;

  /// How the customer paid, when the server sent payment rows. Empty is a real
  /// state (older rows, or a voided sale); the View sheet then falls back to
  /// [paymentMethod] rather than inventing amounts.
  final List<InventorySalePayment> payments;
  double get total => lines.fold(0, (sum, line) => sum + line.subtotal);
  double get totalQuantity => lines.fold(0, (sum, line) => sum + line.quantity);

  /// What the server took off, and why (Phase 4 F4). Zero means none was given.
  final double discountAmount;
  final String discountReason;

  /// The VAT split of the sale, from the server. Both zero on a non-VAT store.
  final double vatableSales;
  final double vatAmount;
  final bool vatRegistered;

  /// Untaxed non-cash payment fee sum, and whether the sale used utang credit pricing.
  final double paymentFee;
  final bool creditSale;
  final String? bodegaStatus;
  final String orNumber;

  /// What the customer actually owed: the lines less the discount plus any payment fee.
  /// The sheet's total bar shows this, so a discounted or fee-bearing sale reconciles.
  double get amountDue => total - discountAmount + paymentFee;

  String? get _normalizedBodegaStatus => bodegaStatus?.trim().toUpperCase();

  /// True once all Bodega pickup lines for this sale have been released.
  bool get isBodegaReleased =>
      _normalizedBodegaStatus == 'RELEASED' ||
      _normalizedBodegaStatus == 'ACCOMPLISHED';

  /// True when some (but not all) Bodega pickup lines have been released.
  bool get isBodegaPartial => _normalizedBodegaStatus == 'PARTIAL';

  /// True when the sale is paid at the till but still waiting on Bodega pickup.
  bool get isAwaitingBodega =>
      status == InventorySaleStatus.completed &&
      _normalizedBodegaStatus != null &&
      !isBodegaReleased;

  /// Unified general status shown on transaction tables, dashboard, and details sheet.
  String get displayStatusLabel {
    if (status == InventorySaleStatus.completed) {
      if (isBodegaPartial) return 'Partial Pickup';
      if (isAwaitingBodega) return 'Pending Pickup';
    }
    return status.label;
  }

  /// Short Bodega badge label for table rows, or null when no Bodega shelf was involved.
  String? get bodegaBadgeLabel {
    if (_normalizedBodegaStatus == null) return null;
    if (isBodegaReleased) return 'Bodega: Released';
    if (isBodegaPartial) return 'Bodega: Partial';
    return 'Awaiting Bodega';
  }

  /// Full Bodega pickup status sentence for the transaction details sheet.
  String? get bodegaDetailLabel {
    if (_normalizedBodegaStatus == null) return null;
    if (isBodegaReleased) return 'Released (Picked up)';
    if (isBodegaPartial) return 'Partially picked up';
    return 'Awaiting Bodega pickup';
  }
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
    required this.total,
    this.lines = const [],
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
  final double total;

  /// Every line of the return, for the read-only details sheet.
  ///
  /// [productName] and [quantity] stay as the single-line summary the table
  /// needs; the sheet shows the full document, so a multi-line return is not
  /// flattened into its first item.
  final List<InventorySaleLine> lines;
}
