// Phase 8 F1 (decision 20): supplier returns, what a delivery can still give
// back, and the numbered credit note a return mints.
//
// The wire shapes come from `apps/inventory` — the `returnable` action of
// `GoodsReceiptViewSet`, `SupplierReturnSerializer` and
// `SupplierCreditNoteSerializer` — never from a guess. Every quantity and money
// figure is a 2-decimal STRING (DRF's DecimalField) and is parsed, not coerced:
// a returnable of `0.00` and a missing one are different facts.

import 'package:client/data/models/json_field.dart';

/// One receipt LINE and how much of it can still go back to the supplier
/// (`GET /goods-receipts/{id}/returnable/`).
///
/// Every quantity is in THAT line's package unit (a BAG line answers in bags),
/// because that is the unit the clerk saw when the delivery arrived and the unit
/// `POST /supplier-returns/` accepts.
class SupplierReturnableLine {
  const SupplierReturnableLine({
    required this.receiptLineId,
    required this.variantId,
    required this.variantName,
    required this.unit,
    required this.delivered,
    required this.returned,
    required this.returnable,
  });

  /// The id the return POST names in `lines[].receipt_line`.
  final int receiptLineId;
  final int variantId;
  final String variantName;

  /// The package unit code this line was received in (`BAG`, `BOX`, …).
  final String unit;

  /// What the line brought in.
  final double delivered;

  /// What past returns already took off this line.
  final double returned;

  /// `min(delivered - returned, this receipt's batches' current qty)` — the
  /// server's own cap, so a delivery whose bags were sold cannot give them back.
  final double returnable;

  /// The POST refuses a zero quantity, so a line with nothing left offers none.
  bool get canReturn => returnable > 0;

  factory SupplierReturnableLine.fromJson(Map<String, dynamic> json) =>
      SupplierReturnableLine(
        receiptLineId: intField(json, 'receipt_line'),
        variantId: intField(json, 'variant'),
        variantName: json['variant_name'] as String? ?? '',
        unit: stringField(json, 'unit'),
        delivered: decimalField(json, 'delivered'),
        returned: decimalField(json, 'returned'),
        returnable: decimalField(json, 'returnable'),
      );
}

/// One batch a return line drew from: the provenance of the stock that left.
class SupplierReturnDeduction {
  const SupplierReturnDeduction({
    required this.id,
    required this.batchId,
    required this.qty,
    required this.unitCostLanded,
  });

  final int id;
  final int batchId;

  /// Base units taken from this batch.
  final double qty;

  /// The landed unit cost the goods were valued at (a snapshot).
  final double unitCostLanded;

  factory SupplierReturnDeduction.fromJson(Map<String, dynamic> json) =>
      SupplierReturnDeduction(
        id: intField(json, 'id'),
        batchId: intField(json, 'batch'),
        qty: decimalField(json, 'qty'),
        unitCostLanded: decimalField(json, 'unit_cost_landed'),
      );
}

/// One returned quantity: what the clerk typed, what left the shelf, what it
/// was worth.
class SupplierReturnLine {
  const SupplierReturnLine({
    required this.id,
    required this.receiptLineId,
    required this.qty,
    required this.baseQty,
    required this.creditValue,
    required this.deductions,
  });

  final int id;
  final int receiptLineId;

  /// The quantity in the receipt line's package unit — what the clerk entered.
  final double qty;

  /// The stock that actually left, in base units.
  final double baseQty;

  /// `Σ(deduction qty × landed cost)`, rounded once by the server.
  final double creditValue;
  final List<SupplierReturnDeduction> deductions;

  factory SupplierReturnLine.fromJson(Map<String, dynamic> json) =>
      SupplierReturnLine(
        id: intField(json, 'id'),
        receiptLineId: intField(json, 'receipt_line'),
        qty: decimalField(json, 'qty'),
        baseQty: decimalField(json, 'base_qty'),
        creditValue: decimalField(json, 'credit_value'),
        deductions: nestedList(
          json,
          'deductions',
          SupplierReturnDeduction.fromJson,
        ),
      );
}

/// Goods that went BACK to a supplier, with the credit note it minted
/// (`SupplierReturnSerializer`).
///
/// Append-only: a return is written inside the transaction that moves the stock,
/// so nothing here is ever edited. The credit note is FLATTENED onto the return
/// (`credit_note_number`/`_total`/`_remaining`) because a payables list needs
/// the number, not a sub-object — and because a pre-B3 return legitimately has
/// no note at all (nulls, not an error).
class SupplierReturn {
  const SupplierReturn({
    required this.id,
    required this.receiptId,
    required this.supplierId,
    required this.supplierName,
    required this.purchaseOrderId,
    required this.billId,
    required this.reason,
    required this.createdByName,
    required this.createdAt,
    required this.creditNoteNumber,
    required this.creditNoteTotal,
    required this.creditNoteRemaining,
    required this.lines,
  });

  final int id;
  final int receiptId;
  final int supplierId;
  final String supplierName;
  final int? purchaseOrderId;

  /// Null when the receipt created no bill (pre-Phase-5 or zero-value), which
  /// leaves the note's whole total as supplier credit.
  final int? billId;
  final String reason;
  final String createdByName;
  final DateTime? createdAt;

  /// `CN-YYYYMMDD-NNNN` — the number a clerk quotes to the supplier.
  final String? creditNoteNumber;

  /// What the goods were worth.
  final double? creditNoteTotal;

  /// What the source bill could not absorb, so it stays applyable to a later
  /// bill of that supplier.
  final double? creditNoteRemaining;
  final List<SupplierReturnLine> lines;

  factory SupplierReturn.fromJson(Map<String, dynamic> json) => SupplierReturn(
    id: intField(json, 'id'),
    receiptId: intField(json, 'receipt'),
    supplierId: intField(json, 'supplier'),
    supplierName: json['supplier_name'] as String? ?? '',
    purchaseOrderId: json['purchase_order'] == null
        ? null
        : intField(json, 'purchase_order'),
    billId: json['bill'] == null ? null : intField(json, 'bill'),
    reason: stringField(json, 'reason'),
    createdByName: json['created_by_name'] as String? ?? '',
    createdAt: nullableDateField(json, 'created_at'),
    creditNoteNumber: _text(json, 'credit_note_number'),
    creditNoteTotal: _decimalOrNull(json, 'credit_note_total'),
    creditNoteRemaining: _decimalOrNull(json, 'credit_note_remaining'),
    lines: nestedList(json, 'lines', SupplierReturnLine.fromJson),
  );
}

/// The numbered credit a supplier return minted (`SupplierCreditNoteSerializer`).
///
/// Read-only evidence of credit the shop is owed: the only figure that ever
/// moves is [remainingAmount], through a CREDIT payment. Its VAT is the SOURCE
/// bill's snapshot, never recomputed here.
class SupplierCreditNote {
  const SupplierCreditNote({
    required this.id,
    required this.number,
    required this.supplierId,
    required this.supplierName,
    required this.supplierReturnId,
    required this.sourceBillId,
    required this.value,
    required this.vatRate,
    required this.vatInclusive,
    required this.vatAmount,
    required this.totalAmount,
    required this.remainingAmount,
    required this.appliedAmount,
    required this.createdAt,
  });

  final int id;
  final String number;
  final int supplierId;
  final String supplierName;
  final int? supplierReturnId;
  final int? sourceBillId;

  /// The goods' value before VAT is applied or extracted.
  final double value;
  final double vatRate;
  final bool vatInclusive;
  final double vatAmount;
  final double totalAmount;

  /// What is left to spend — the figure an "apply credit" picker offers.
  final double remainingAmount;

  /// `total - remaining`, derived by the server.
  final double appliedAmount;
  final DateTime? createdAt;

  /// True while the note can still settle money. `?open=true` sends only these.
  bool get isOpen => remainingAmount > 0;

  factory SupplierCreditNote.fromJson(Map<String, dynamic> json) =>
      SupplierCreditNote(
        id: intField(json, 'id'),
        number: stringField(json, 'number'),
        supplierId: intField(json, 'supplier'),
        supplierName: json['supplier_name'] as String? ?? '',
        supplierReturnId: json['supplier_return'] == null
            ? null
            : intField(json, 'supplier_return'),
        sourceBillId: json['source_bill'] == null
            ? null
            : intField(json, 'source_bill'),
        value: decimalField(json, 'value'),
        vatRate: decimalField(json, 'vat_rate'),
        vatInclusive: _requiredBool(json, 'vat_inclusive'),
        vatAmount: decimalField(json, 'vat_amount'),
        totalAmount: decimalField(json, 'total_amount'),
        remainingAmount: decimalField(json, 'remaining_amount'),
        appliedAmount: decimalField(json, 'applied_amount'),
        createdAt: nullableDateField(json, 'created_at'),
      );
}

/// A boolean the server always sends. Absent is a contract break: guessing the
/// VAT style would print a VAT-exclusive note's total as if the tax were inside.
bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Missing required bool field "$key"');
}

/// A nullable string that the API may send as `null` or omit entirely.
String? _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  return null;
}

/// A decimal that a pre-B3 row legitimately leaves null (a return with no note).
///
/// Present-but-unparseable still fails loudly: null is the server saying "there
/// is no note", a bad string is a contract break.
double? _decimalOrNull(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return decimalField(json, key);
}
