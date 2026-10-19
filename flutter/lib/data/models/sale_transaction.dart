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
  });

  final int variantUomId;
  final String variantUomCode;
  final double qty;
  final double unitPrice;
  final double subtotal;

  factory TransactionLineItem.fromJson(Map<String, dynamic> json) =>
      TransactionLineItem(
        variantUomId: intField(json, 'variant_uom'),
        variantUomCode: stringField(json, 'variant_uom_code'),
        qty: decimalField(json, 'qty'),
        unitPrice: decimalField(json, 'unit_price'),
        subtotal: decimalField(json, 'subtotal'),
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
    required this.items,
  });

  final int id;
  final String number;
  final int customerId;
  final String status;
  final String validUntil;
  final List<QuotationLineItem> items;

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
      validUntil: stringField(json, 'valid_until'),
      items: items
          .map((i) => QuotationLineItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// GET /api/v1/sales-orders/ rows. `quotationId` is the order's origin
/// quotation when it has one — the quotation-to-order flow, made traceable.
class SalesOrderRecord {
  const SalesOrderRecord({
    required this.id,
    required this.number,
    required this.customerId,
    required this.quotationId,
    required this.status,
  });

  final int id;
  final String number;
  final int customerId;
  final int? quotationId;
  final String status;

  factory SalesOrderRecord.fromJson(Map<String, dynamic> json) =>
      SalesOrderRecord(
        id: intField(json, 'id'),
        number: stringField(json, 'order_no'),
        customerId: intField(json, 'customer'),
        quotationId: json['quotation'] as int?,
        status: stringField(json, 'status'),
      );
}
