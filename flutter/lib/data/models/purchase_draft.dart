/// What "New purchase order" collects, in the shape the server accepts.
///
/// `POST /api/v1/purchase-orders/` takes the supplier, an optional expected
/// delivery and notes, and the LINES nested in the same body — there is no
/// `/po-items/` endpoint, so a line cannot be created on its own.
///
/// `status` and `created_by` are deliberately absent: both are read-only
/// server-side (`status` moves through `place/` and `cancel/`, `created_by` is
/// the caller), and sending them would be a value the server ignores.
class PurchaseOrderDraft {
  const PurchaseOrderDraft({
    required this.supplierId,
    required this.lines,
    this.expectedDelivery,
    this.notes = '',
  });

  final int supplierId;
  final List<PurchaseOrderLineDraft> lines;
  final DateTime? expectedDelivery;
  final String notes;

  double get total => lines.fold(0, (sum, line) => sum + line.subtotal);

  Map<String, dynamic> toJson() => {
    'supplier': supplierId,
    if (expectedDelivery != null)
      'expected_delivery': _isoDate(expectedDelivery!),
    if (notes.isNotEmpty) 'notes': notes,
    'items': [for (final line in lines) line.toJson()],
  };

  /// `YYYY-MM-DD`. A `DateField` server-side rejects a timestamp, and a timezone
  /// shift on a delivery date is a fact nobody wants to argue about.
  static String _isoDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

/// One order line: the variant, how many, and what each costs.
class PurchaseOrderLineDraft {
  const PurchaseOrderLineDraft({
    required this.variantId,
    required this.quantity,
    required this.unitCost,
    this.variantName = '',
  });

  final int variantId;
  final double quantity;
  final double unitCost;

  /// Display only — never sent. The picker needs a label, the wire needs the id.
  final String variantName;

  double get subtotal => quantity * unitCost;

  Map<String, dynamic> toJson() => {
    'variant': variantId,
    'ordered_qty': quantity,
    'unit_cost': unitCost,
  };
}
