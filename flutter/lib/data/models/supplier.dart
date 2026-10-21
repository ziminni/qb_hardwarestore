import 'package:client/data/models/json_field.dart';

/// A vendor (decision D-02).
///
/// Shape verified against `apps/inventory/serializers.py::SupplierSerializer`
/// (2026-10-22): `id, company_name, contact_person, phone, email, address,
/// is_active, created_at, updated_at`. Every descriptive field is nullable on
/// the model, so only `id` and `company_name` are required here — a supplier
/// with no phone number is a real row, not a contract break.
class Supplier {
  const Supplier({
    required this.id,
    required this.companyName,
    required this.contactPerson,
    required this.phone,
    required this.email,
    required this.address,
    this.isActive = true,
  });
  final int id;
  final String companyName;
  final String contactPerson;
  final String phone;
  final String email;
  final String address;
  final bool isActive;
  Supplier copyWith({
    String? companyName,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    bool? isActive,
  }) => Supplier(
    id: id,
    companyName: companyName ?? this.companyName,
    contactPerson: contactPerson ?? this.contactPerson,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    address: address ?? this.address,
    isActive: isActive ?? this.isActive,
  );

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: intField(json, 'id'),
    companyName: stringField(json, 'company_name'),
    contactPerson: json['contact_person'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    address: json['address'] as String? ?? '',
    isActive: boolFieldOr(json, 'is_active', or: true),
  );
}

enum PurchaseStatus {
  draft('Draft'),
  ordered('Ordered'),
  partial('Partially Received'),
  complete('Complete'),
  cancelled('Cancelled');

  const PurchaseStatus(this.label);
  final String label;
}

class PurchaseItem {
  const PurchaseItem({
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.quantity,
    required this.receivedQuantity,
    required this.unitCost,
  });
  final String productName;
  final String variantName;
  final String sku;
  final double quantity;
  final double receivedQuantity;
  final double unitCost;
  double get subtotal => quantity * unitCost;

  /// One PO line from `POItemSerializer` (decision D-02).
  ///
  /// The serializer sends `id, po, variant, variant_name, ordered_qty,
  /// unit_cost, received_qty` — it carries **no product name and no SKU**, only
  /// the variant's name. Those two fields therefore come back empty and the
  /// details dialog renders the variant name alone. Inventing a product name
  /// out of the variant name would be a guess shown as if the server said it.
  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
    productName: '',
    variantName: stringField(json, 'variant_name'),
    sku: '',
    quantity: decimalField(json, 'ordered_qty'),
    receivedQuantity: decimalField(json, 'received_qty'),
    unitCost: decimalField(json, 'unit_cost'),
  );
}

/// Maps the server's `PurchaseOrder.Status` choice to the UI enum.
///
/// Uppercase `DRAFT|ORDERED|PARTIAL|COMPLETE|CANCELLED` server-side versus the
/// Flutter enum's lowercase names — mapped explicitly rather than by
/// `toLowerCase`, so an unknown status fails loudly instead of silently
/// rendering as Draft ("not yet sent") on a PO that was actually cancelled.
PurchaseStatus _statusFromString(String value) => switch (value) {
  'DRAFT' => PurchaseStatus.draft,
  'ORDERED' => PurchaseStatus.ordered,
  'PARTIAL' => PurchaseStatus.partial,
  'COMPLETE' => PurchaseStatus.complete,
  'CANCELLED' => PurchaseStatus.cancelled,
  _ => throw FormatException('Unknown purchase order status "$value"'),
};

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.supplierId,
    required this.supplierName,
    required this.orderDate,
    required this.expectedDelivery,
    required this.status,
    required this.createdBy,
    required this.notes,
    required this.items,
  });
  final int id;
  final int supplierId;
  final String supplierName;
  final DateTime orderDate;
  final DateTime? expectedDelivery;
  final PurchaseStatus status;
  final String createdBy;
  final String notes;
  final List<PurchaseItem> items;
  double get total => items.fold(0, (sum, item) => sum + item.subtotal);
  double get orderedQuantity =>
      items.fold(0, (sum, item) => sum + item.quantity);
  double get receivedQuantity =>
      items.fold(0, (sum, item) => sum + item.receivedQuantity);

  /// A purchase order from `PurchaseOrderSerializer` (decision D-02).
  ///
  /// `supplier` is an **id** and the serializer exposes no `supplier_name`, so
  /// [supplierName] starts empty and the viewmodel fills it from the suppliers
  /// it has already loaded. D-02 chose that join over a one-line backend
  /// change, so this file must not pretend the name arrived here.
  factory PurchaseOrder.fromJson(Map<String, dynamic> json) => PurchaseOrder(
    id: intField(json, 'id'),
    supplierId: intField(json, 'supplier'),
    supplierName: '',
    orderDate: DateTime.parse(stringField(json, 'order_date')),
    expectedDelivery: nullableDateField(json, 'expected_delivery'),
    status: _statusFromString(stringField(json, 'status')),
    createdBy: json['created_by_name'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    items: nestedList(json, 'items', PurchaseItem.fromJson),
  );

  /// Returns this order with its supplier's name attached.
  ///
  /// A value copy rather than a mutable field: the resolved name is derived
  /// state the viewmodel owns, so the wire model stays immutable.
  PurchaseOrder withSupplierName(String name) => PurchaseOrder(
    id: id,
    supplierId: supplierId,
    supplierName: name,
    orderDate: orderDate,
    expectedDelivery: expectedDelivery,
    status: status,
    createdBy: createdBy,
    notes: notes,
    items: items,
  );
}
