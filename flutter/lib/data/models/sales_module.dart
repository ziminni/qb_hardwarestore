import 'package:client/data/models/sale_transaction.dart';

enum SalesQuoteStatus { draft, sent, accepted, expired }

enum SalesOrderStatus { confirmed, processing, ready, completed }

/// A quotation as the sales screens render it.
///
/// [items] are the SAME wire line type the service already parses
/// ([QuotationLineItem]) — the list endpoint returns them nested, so the View
/// sheet (decision D-02) needs no extra fetch and no second model of the same
/// row.
class SalesQuotation {
  const SalesQuotation(
    this.number,
    this.customer,
    this.date,
    this.validUntil,
    this.total,
    this.status, {
    this.items = const [],
    this.notes,
  });
  final String number;
  final String customer;
  final DateTime date;
  final DateTime validUntil;
  final double total;
  final SalesQuoteStatus status;
  final List<QuotationLineItem> items;
  final String? notes;
}

/// A sales order as the sales screens render it. [items] mirror
/// [QuotationLineItem]'s reasoning: already on the wire, no detail fetch needed.
class SalesOrderRecord {
  const SalesOrderRecord(
    this.number,
    this.customer,
    this.date,
    this.total,
    this.status, {
    this.items = const [],
    this.notes,
  });
  final String number;
  final String customer;
  final DateTime date;
  final double total;
  final SalesOrderStatus status;
  final List<OrderLineItem> items;
  final String? notes;
}

