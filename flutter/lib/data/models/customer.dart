import 'package:client/data/models/json_field.dart';

/// A customer, as `CustomerSerializer` exposes one.
///
/// Deliberately minimal: the POS needs to **identify** a customer at checkout, not to
/// manage them. Which slice of customer master data the POS eventually owns is
/// [decision 14](../../../planning/api-integration/decisions/14-customer-master-data-scope.md),
/// still open, and this file should not pre-empt it.
///
/// Verified contract (2026-10-16) from `apps/pos/serializers.py::CustomerSerializer`:
/// `id, name, customer_type, contact_details, tin_no, total_credit_limit, is_active,
/// created_at, updated_at`.
class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.customerType,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
    id: intField(json, 'id'),
    name: stringField(json, 'name'),
    // Optional on the wire: the serializer always sends it, but a customer is still
    // identifiable without it, so a missing type must not throw.
    customerType: (json['customer_type'] as String?) ?? '',
  );

  final int id;
  final String name;
  final String customerType;

  /// The name `seed_demo` gives the anonymous-sale customer.
  static const walkInName = 'Walk-in Customer';
}
