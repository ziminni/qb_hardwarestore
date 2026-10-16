import 'package:client/data/models/json_field.dart';

/// The four customer types the backend actually carries.
///
/// Four, not three: decision 14's stub listed WALK_IN / REGULAR / CONTRACTOR, but
/// `apps/pos/models.py` and `migrations/0001_initial.py` both carry **CONSTRUCTION_FIRM**,
/// and `seed_demo` seeds `Dela Cruz Construction` with it. A picker built from the stub's
/// list would mislabel every firm customer — and this project has two business entities, so
/// that is not a hypothetical.
enum CustomerType {
  walkIn('WALK_IN', 'Walk-in'),
  regular('REGULAR', 'Regular'),
  contractor('CONTRACTOR', 'Contractor'),
  constructionFirm('CONSTRUCTION_FIRM', 'Construction Firm'),

  /// A type this client does not know yet.
  ///
  /// The backend is free to add one; falling back keeps the customer in the picker rather
  /// than silently shortening it, which would read as "that customer does not exist".
  unknown('', 'Unknown');

  const CustomerType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static CustomerType fromApiValue(String? value) {
    for (final type in values) {
      if (type != unknown && type.apiValue == value) return type;
    }
    return unknown;
  }

  /// True for the anonymous-sale placeholder, which is not a customer record at all.
  bool get isAnonymous => this == walkIn;
}

/// A customer, as `CustomerSerializer` exposes one.
///
/// Verified contract (2026-10-16) from `apps/pos/serializers.py::CustomerSerializer`:
/// `id, name, customer_type, contact_details, tin_no, total_credit_limit, is_active,
/// created_at, updated_at`.
///
/// Deliberately minimal: the POS needs to **identify** a customer at checkout and, since
/// decision 14, to create one on a **name + type** record. The rest of the fields are on the
/// wire but are not surfaced, because a cashier is not asked for a TIN or a credit limit —
/// decision 14's locked decision 1.
class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.customerType,
    this.totalCreditLimit = 0,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: intField(json, 'id'),
    name: stringField(json, 'name'),
    // Optional on the wire: the serializer always sends it, but a customer is still
    // identifiable without it, so a missing type must not throw.
    customerType: (json['customer_type'] as String?) ?? '',
    totalCreditLimit: json['total_credit_limit'] == null
        ? 0
        : decimalField(json, 'total_credit_limit'),
  );

  final int id;
  final String name;

  /// The raw wire value, kept so the model stays API-faithful.
  final String customerType;

  /// The credit limit, **where 0 means NOT SET** rather than "no credit allowed".
  ///
  /// Pinned before the panel was built: every customer in the database sits at 0.00 and
  /// nothing in the codebase ever sets the field, so warning on 0 would fire on every utang
  /// sale for every customer - which is how a warning becomes something a cashier ignores.
  /// The panel therefore warns only when this is greater than zero.
  final double totalCreditLimit;

  /// True when a limit has actually been configured.
  bool get hasCreditLimit => totalCreditLimit > 0;

  /// The same value as a known type, or [CustomerType.unknown].
  CustomerType get type => CustomerType.fromApiValue(customerType);

  /// True when this is the shared placeholder an anonymous sale is posted against.
  bool get isWalkIn => type.isAnonymous;

  /// The name `seed_demo` gives the anonymous-sale customer.
  static const walkInName = 'Walk-in Customer';

  @override
  String toString() => '$name (#$id)';
}

/// One customer's outstanding utang, as `/api/v1/ledgers/aging/` reports it.
///
/// Sourced from the aging report rather than the per-customer ledger list, because aging
/// already returns one group per customer carrying `total_balance`, `open_count` and
/// `overdue_count` — exactly the panel's lines — so no client-side summing is needed and no
/// second call. The report covers OPEN / PARTIAL / OVERDUE entries, which is what
/// "outstanding" means here.
class CustomerLedgerSummary {
  const CustomerLedgerSummary({
    required this.customerId,
    required this.customerName,
    required this.totalBalance,
    required this.openCount,
    required this.overdueCount,
  });

  /// A customer the aging report does not mention, i.e. one with no outstanding debt.
  ///
  /// This is the commonest case at the till, so it is a zero summary rather than an error:
  /// the report lists only customers who OWE, and reporting a failure for a customer with a
  /// clean account would put an error in front of the cashier for the normal case.
  factory CustomerLedgerSummary.empty(int customerId, {String name = ''}) =>
      CustomerLedgerSummary(
        customerId: customerId,
        customerName: name,
        totalBalance: 0,
        openCount: 0,
        overdueCount: 0,
      );

  factory CustomerLedgerSummary.fromJson(Map<String, dynamic> json) =>
      CustomerLedgerSummary(
        customerId: intField(json, 'customer_id'),
        customerName: stringField(json, 'customer_name'),
        totalBalance: decimalField(json, 'total_balance'),
        openCount: intField(json, 'open_count'),
        overdueCount: intField(json, 'overdue_count'),
      );

  final int customerId;
  final String customerName;
  final double totalBalance;
  final int openCount;
  final int overdueCount;

  bool get hasDebt => totalBalance > 0;
}
