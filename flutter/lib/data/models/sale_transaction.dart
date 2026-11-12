import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/json_field.dart';

/// Server rows behind the sales screens that render transactions.
///
/// Shapes verified against `backend_django/apps/pos/serializers.py`
/// (`SalesTransactionSerializer` + nested item/payment serializers).
/// `customer_name` rides the row, so no per-row customer fetch is needed.
class TransactionLineItem {
  const TransactionLineItem({
    required this.variantUomId,
    required this.variantUomCode,
    required this.qty,
    required this.unitPrice,
    required this.subtotal,
    this.storedAtName = '',
  });

  final int variantUomId;
  final String variantUomCode;
  final double qty;
  final double unitPrice;
  final double subtotal;

  /// Where the product is picked up, as the SALE recorded it (Phase 5 B4).
  /// Empty on a row written before B4.
  final String storedAtName;

  factory TransactionLineItem.fromJson(Map<String, dynamic> json) =>
      TransactionLineItem(
        variantUomId: intField(json, 'variant_uom'),
        variantUomCode: stringField(json, 'variant_uom_code'),
        qty: decimalField(json, 'qty'),
        unitPrice: decimalField(json, 'unit_price'),
        subtotal: decimalField(json, 'subtotal'),
        storedAtName: json['stored_at_name'] is String
            ? json['stored_at_name'] as String
            : '',
      );
}

class TransactionPayment {
  const TransactionPayment({
    required this.method,
    required this.amountTendered,
  });

  final String method;
  final double amountTendered;

  factory TransactionPayment.fromJson(Map<String, dynamic> json) =>
      TransactionPayment(
        method: stringField(json, 'method'),
        amountTendered: decimalField(json, 'amount_tendered'),
      );
}

class TransactionRecord {
  const TransactionRecord({
    required this.id,
    required this.transactionNo,
    required this.transDate,
    required this.customerId,
    required this.customerName,
    required this.cashierName,
    required this.source,
    required this.originalTransactionId,
    required this.status,
    required this.grandTotal,
    required this.items,
    required this.payments,
    this.discountAmount = 0,
    this.discountReason = '',
    this.vatableSales = 0,
    this.vatAmount = 0,
    this.vatRegistered = true,
  });

  final int id;
  final String transactionNo;
  final DateTime transDate;
  final int customerId;
  final String customerName;
  final String cashierName;
  final String source;
  final int? originalTransactionId;
  final String status;
  final double grandTotal;
  final List<TransactionLineItem> items;
  final List<TransactionPayment> payments;

  /// What was taken off the gross, and why (Phase 4 B1). Zero means no discount,
  /// which is every sale written before discounts existed.
  final double discountAmount;
  final String discountReason;

  /// The VAT breakdown of [grandTotal], as the server computed it. Both are zero
  /// when the store is not VAT registered.
  final double vatableSales;
  final double vatAmount;
  final bool vatRegistered;

  factory TransactionRecord.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw FormatException('Missing required list field "items"');
    }
    final payments = json['payments'];
    if (payments is! List) {
      throw FormatException('Missing required list field "payments"');
    }
    return TransactionRecord(
      id: intField(json, 'id'),
      transactionNo: stringField(json, 'transaction_no'),
      transDate: DateTime.parse(stringField(json, 'trans_date')),
      customerId: intField(json, 'customer'),
      customerName: stringField(json, 'customer_name'),
      cashierName: stringField(json, 'cashier_name'),
      source: stringField(json, 'source'),
      originalTransactionId: json['original_transaction'] as int?,
      status: stringField(json, 'status'),
      grandTotal: decimalField(json, 'grand_total'),
      // Phase 4 B1 fields. A body from before them reads as "no discount, VAT not
      // split", which is exactly what those sales were.
      discountAmount: double.tryParse('${json['discount_amount']}') ?? 0,
      discountReason: json['discount_reason'] is String
          ? json['discount_reason'] as String
          : '',
      vatableSales: double.tryParse('${json['vatable_sales']}') ?? 0,
      vatAmount: double.tryParse('${json['vat_amount']}') ?? 0,
      vatRegistered: json['vat_registered'] is bool
          ? json['vat_registered'] as bool
          : true,
      items: items
          .map((i) => TransactionLineItem.fromJson(i as Map<String, dynamic>))
          .toList(),
      payments: payments
          .map((p) => TransactionPayment.fromJson(p as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One quotation line as the server stores it.
class QuotationLineItem {
  const QuotationLineItem({
    required this.variantUomId,
    required this.qty,
    required this.unitPrice,
  });

  final int variantUomId;
  final double qty;
  final double unitPrice;

  factory QuotationLineItem.fromJson(Map<String, dynamic> json) =>
      QuotationLineItem(
        variantUomId: intField(json, 'variant_uom'),
        qty: decimalField(json, 'qty'),
        unitPrice: decimalField(json, 'unit_price'),
      );
}

/// GET /api/v1/quotations/ rows. Customer display names join client-side
/// through CustomerService — the wire carries only the customer id.
class QuotationRecord {
  const QuotationRecord({
    required this.id,
    required this.number,
    required this.customerId,
    required this.status,
    required this.validUntil,
    required this.createdAt,
    required this.items,
    this.notes,
  });

  final int id;
  final String number;
  final int customerId;
  final String status;

  /// May be null — a quotation need not expire. See the viewmodel fallback.
  final String? validUntil;
  final String createdAt;
  final List<QuotationLineItem> items;

  /// Free-text note the customer asked for. Optional on the wire; the View
  /// sheet (decision D-02) shows it when present and omits the row otherwise.
  final String? notes;

  factory QuotationRecord.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw FormatException('Missing required list field "items"');
    }
    return QuotationRecord(
      id: intField(json, 'id'),
      number: stringField(json, 'quotation_no'),
      customerId: intField(json, 'customer'),
      status: stringField(json, 'status'),
      validUntil: json['valid_until'] as String?,
      createdAt: stringField(json, 'created_at'),
      notes: json['notes'] as String?,
      items: items
          .map((i) => QuotationLineItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// GET /api/v1/sales-orders/ rows. `quotationId` is the order's origin
/// quotation when it has one — the quotation-to-order flow, made traceable.
class OrderLineItem {
  const OrderLineItem({
    required this.variantUomId,
    required this.qty,
    required this.unitPrice,
  });

  final int variantUomId;
  final double qty;
  final double unitPrice;

  factory OrderLineItem.fromJson(Map<String, dynamic> json) => OrderLineItem(
    variantUomId: intField(json, 'variant_uom'),
    qty: decimalField(json, 'qty'),
    unitPrice: decimalField(json, 'unit_price'),
  );
}

class SalesOrderRow {
  const SalesOrderRow({
    required this.id,
    required this.number,
    required this.customerId,
    required this.quotationId,
    required this.status,
    required this.createdAt,
    required this.items,
    this.notes,
  });

  final int id;
  final String number;
  final int customerId;
  final int? quotationId;
  final String status;
  final String createdAt;
  final List<OrderLineItem> items;

  /// Free-text note from the order. Optional on the wire — the View sheet
  /// shows it when present and omits the row otherwise.
  final String? notes;

  double get total =>
      items.fold<double>(0, (sum, i) => sum + i.qty * i.unitPrice);

  factory SalesOrderRow.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw FormatException('Missing required list field "items"');
    }
    return SalesOrderRow(
      id: intField(json, 'id'),
      number: stringField(json, 'order_no'),
      customerId: intField(json, 'customer'),
      quotationId: json['quotation'] as int?,
      status: stringField(json, 'status'),
      createdAt: stringField(json, 'created_at'),
      notes: json['notes'] as String?,
      items: items
          .map((i) => OrderLineItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One line of a sales order the client is CREATING (Phase 5 F3 follow-up).
///
/// The wire names the SELLING UNIT (`variant_uom`) rather than the variant: a
/// line is counted and priced in the unit the customer asked for, and the server
/// refuses a fractional count of a whole unit (`WHOLE_UNIT_QUANTITY`).
class SalesOrderLineDraft {
  const SalesOrderLineDraft({
    required this.variantUomId,
    required this.qty,
    required this.unitPrice,
  });

  final int variantUomId;
  final double qty;
  final double unitPrice;

  double get subtotal => qty * unitPrice;

  Map<String, dynamic> toJson() => {
    'variant_uom': variantUomId,
    'qty': qty,
    // 2 dp text: DRF's DecimalField takes it, and a double can serialize as
    // 249.99999999999997 for a price nobody typed.
    'unit_price': unitPrice.toStringAsFixed(2),
  };
}

/// What "New sales order" collects: `POST /api/v1/sales-orders/`
/// (ENDPOINTS.md §3.1, Phase 5 F3 follow-up).
///
/// `status` is deliberately absent — the server defaults the order to CONFIRMED
/// and the client has no status control at all (there is no fulfil-to-sale path
/// and no edit route in this build). `delivery` is optional and carries the same
/// object a till sale does ([DeliveryDraft]), so the two forms cannot disagree
/// about what a delivery is.
class SalesOrderDraft {
  const SalesOrderDraft({
    required this.customerId,
    required this.lines,
    this.notes = '',
    this.delivery,
  });

  final int customerId;
  final List<SalesOrderLineDraft> lines;

  /// Free text the customer asked for. Omitted when blank so the server keeps
  /// its own empty default.
  final String notes;

  /// The trip described on the Deliver section, or null when the customer
  /// collects. The FEE lives on the delivery row only: an order carries no money
  /// total on the wire.
  final DeliveryDraft? delivery;

  /// What the GOODS come to. Not the order total: a delivery fee is on its
  /// delivery row and is never discounted.
  double get goodsTotal => lines.fold<double>(0, (sum, l) => sum + l.subtotal);

  Map<String, dynamic> toJson() => {
    'customer': customerId,
    if (notes.isNotEmpty) 'notes': notes,
    'items': [for (final line in lines) line.toJson()],
    if (delivery != null) 'delivery': delivery!.toJson(),
  };
}
