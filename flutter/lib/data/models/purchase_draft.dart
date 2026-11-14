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
    this.discountAmount = 0,
    this.vatInclusive = true,
  });

  final int supplierId;
  final List<PurchaseOrderLineDraft> lines;
  final DateTime? expectedDelivery;
  final String notes;

  /// Pesos off the whole order (Phase 5 B2). The server caps it at the gross
  /// (`INVALID_PO`) and lets it change only while the order is DRAFT.
  ///
  /// The header discount is what the receipt's BILL inherits; it is deliberately
  /// not in a batch's landed cost, which stays `unit_cost / conversion_factor`.
  final double discountAmount;

  /// Whether the line prices already contain VAT. The server's own default, so
  /// an order created before this control keeps its meaning.
  final bool vatInclusive;

  double get total => lines.fold(0, (sum, line) => sum + line.subtotal);

  Map<String, dynamic> toJson() => {
    'supplier': supplierId,
    if (expectedDelivery != null)
      'expected_delivery': _isoDate(expectedDelivery!),
    if (notes.isNotEmpty) 'notes': notes,
    // 2 dp text, like every money value this app writes: a double can
    // serialize as 99.99999999999999 and the server would store that.
    if (discountAmount > 0)
      'discount_amount': discountAmount.toStringAsFixed(2),
    'vat_inclusive': vatInclusive,
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

/// One order line: the variant, the selling unit it is counted in, how many,
/// and what each costs in that unit.
class PurchaseOrderLineDraft {
  const PurchaseOrderLineDraft({
    required this.variantId,
    required this.quantity,
    required this.unitCost,
    this.variantUomId,
    this.variantName = '',
  });

  final int variantId;

  /// The selling unit the line is COUNTED in (Phase 5, decision 18): a
  /// `VariantUOM` id, so `ordered_qty` and `unit_cost` are per that unit.
  ///
  /// Null means "the variant's base unit": the server then defaults the line to
  /// its base selling unit, which is what a pre-B1 line meant.
  final int? variantUomId;

  final double quantity;
  final double unitCost;

  /// Display only — never sent. The picker needs a label, the wire needs the id.
  final String variantName;

  double get subtotal => quantity * unitCost;

  Map<String, dynamic> toJson() => {
    'variant': variantId,
    if (variantUomId != null) 'variant_uom': variantUomId,
    'ordered_qty': quantity,
    'unit_cost': unitCost,
  };
}
