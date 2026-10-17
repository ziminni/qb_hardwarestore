enum SalesQuoteStatus { draft, sent, accepted, expired }

enum SalesOrderStatus { confirmed, processing, ready, completed }

class SalesQuotation {
  const SalesQuotation(
    this.number,
    this.customer,
    this.date,
    this.validUntil,
    this.total,
    this.status,
  );
  final String number;
  final String customer;
  final DateTime date;
  final DateTime validUntil;
  final double total;
  final SalesQuoteStatus status;
}

class SalesOrderRecord {
  const SalesOrderRecord(
    this.number,
    this.customer,
    this.date,
    this.total,
    this.status,
  );
  final String number;
  final String customer;
  final DateTime date;
  final double total;
  final SalesOrderStatus status;
}

