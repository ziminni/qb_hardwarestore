enum SalesQuoteStatus { draft, sent, accepted, expired }

enum SalesOrderStatus { confirmed, processing, ready, completed }

enum SalesReceivableStatus { current, dueSoon, overdue }

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

class SalesCustomerRecord {
  const SalesCustomerRecord(
    this.id,
    this.name,
    this.contact,
    this.type,
    this.transactions,
    this.totalSpent,
  );
  final String id;
  final String name;
  final String contact;
  final String type;
  final int transactions;
  final double totalSpent;
}

class SalesReceivableRecord {
  const SalesReceivableRecord(
    this.invoice,
    this.customer,
    this.dueDate,
    this.total,
    this.paid,
    this.status,
  );
  final String invoice;
  final String customer;
  final DateTime dueDate;
  final double total;
  final double paid;
  final SalesReceivableStatus status;
  double get balance => total - paid;
}
