import 'package:client/data/models/sale_transaction.dart';

enum SalesQuoteStatus { draft, sent, accepted, expired }

/// The statuses an order can really carry (Phase 7 F1, decision 19).
///
/// Legacy `PROCESSING`/`READY` rows still exist in the database; the server
/// reads them as CONFIRMED on the wire, so no member here stands for them.
enum SalesOrderStatus { confirmed, partial, cancelled, completed }

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
    this.id,
    this.number,
    this.customer,
    this.date,
    this.total,
    this.status, {
    this.items = const [],
    this.notes,
  });

  /// The order's database id: the Edit and Cancel actions address it.
  final int id;
  final String number;
  final String customer;
  final DateTime date;
  final double total;
  final SalesOrderStatus status;
  final List<OrderLineItem> items;
  final String? notes;
}
