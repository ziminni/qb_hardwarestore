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
    this.termsDays = 0,
  });
  final int id;
  final String companyName;
  final String contactPerson;
  final String phone;
  final String email;
  final String address;
  final bool isActive;

  /// How many days after the goods arrive this supplier's bill falls due
  /// (Phase 5 B2). 0 means "due on receipt", which is the server's default, so
  /// an absent field is read as 0 rather than as an unknown.
  ///
  /// Editing it re-dates NO existing bill: each bill snapshots the terms it was
  /// issued under.
  final int termsDays;

  Supplier copyWith({
    String? companyName,
    String? contactPerson,
    String? phone,
    String? email,
    String? address,
    bool? isActive,
    int? termsDays,
  }) => Supplier(
    id: id,
    companyName: companyName ?? this.companyName,
    contactPerson: contactPerson ?? this.contactPerson,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    address: address ?? this.address,
    isActive: isActive ?? this.isActive,
    termsDays: termsDays ?? this.termsDays,
  );

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
    id: intField(json, 'id'),
    companyName: stringField(json, 'company_name'),
    contactPerson: json['contact_person'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    email: json['email'] as String? ?? '',
    address: json['address'] as String? ?? '',
    isActive: boolFieldOr(json, 'is_active', or: true),
    // A server that predates terms sends nothing; a negative value is a
    // contract break, not a payment window.
    termsDays: _termsDays(json['terms_days']),
  );

  static int _termsDays(Object? value) {
    if (value == null) return 0;
    final parsed = value is int ? value : int.tryParse(value.toString());
    if (parsed == null || parsed < 0) {
      throw FormatException('Field "terms_days" is not a day count: $value');
    }
    return parsed;
  }
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
    this.uomCode = '',
  });
  final String productName;
  final String variantName;
  final String sku;
  final double quantity;
  final double receivedQuantity;
  final double unitCost;

  /// The selling unit these counts are in (Phase 5 B1, decision 18). Empty on a
  /// line from a server that predates units: the numbers are then base units, so
  /// no unit word is invented for them.
  final String uomCode;

  double get subtotal => quantity * unitCost;

  /// One PO line from `POItemSerializer` (decision D-02, Phase 5 B1).
  ///
  /// The serializer sends `id, po, variant, variant_name, variant_uom, uom_code,
  /// conversion_factor, uom_is_whole, ordered_qty, unit_cost, received_qty` — it
  /// carries **no product name and no SKU**, only the variant's name. Those two
  /// fields therefore come back empty and the details dialog renders the variant
  /// name alone. Inventing a product name out of the variant name would be a
  /// guess shown as if the server said it.
  factory PurchaseItem.fromJson(Map<String, dynamic> json) => PurchaseItem(
    productName: '',
    variantName: stringField(json, 'variant_name'),
    sku: '',
    quantity: decimalField(json, 'ordered_qty'),
    receivedQuantity: decimalField(json, 'received_qty'),
    unitCost: decimalField(json, 'unit_cost'),
    uomCode: json['uom_code'] as String? ?? '',
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
    this.discountAmount = 0,
    this.vatInclusive = true,
    this.vatRate,
    this.grossAmount,
    this.netAmount,
    this.vatableAmount,
    this.vatAmount,
    this.serverTotalAmount,
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

  // Phase 5 B2 money on the header (decision 18). The server computes all of
  // it: the discount it accepted, the VAT rate snapshot, and the split. Every
  // figure is null on a payload from a server that predates B2, which is why
  // [hasServerTotals] exists instead of defaulting them to zero.
  final double discountAmount;

  /// Whether the line prices already contain VAT (the server's default).
  final bool vatInclusive;

  /// The rate snapshot taken from `store-settings` when the order was created;
  /// 0 for a non-VAT shop, null on a pre-B2 order.
  final double? vatRate;
  final double? grossAmount;
  final double? netAmount;
  final double? vatableAmount;
  final double? vatAmount;
  final double? serverTotalAmount;

  /// True when the payload carried the server's figures, so the details dialog
  /// shows them instead of re-adding the lines.
  bool get hasServerTotals => serverTotalAmount != null || grossAmount != null;

  /// The total to SHOW: the server's when it said, the line sum otherwise.
  double get displayTotal => serverTotalAmount ?? total;

  double get total => items.fold(0, (sum, item) => sum + item.subtotal);
  double get orderedQuantity =>
      items.fold(0, (sum, item) => sum + item.quantity);
  double get receivedQuantity =>
      items.fold(0, (sum, item) => sum + item.receivedQuantity);

  /// `place/` only leaves DRAFT; any other status answers 400 INVALID_PO_STATE.
  bool get canPlace => status == PurchaseStatus.draft;

  /// `cancel/` refuses an order that already has goods against it
  /// (400 PO_HAS_RECEIPTS) and one that is already cancelled.
  bool get canCancel =>
      (status == PurchaseStatus.draft || status == PurchaseStatus.ordered) &&
      receivedQuantity == 0;

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
    discountAmount: _moneyOrZero(json, 'discount_amount'),
    vatInclusive: boolFieldOr(json, 'vat_inclusive', or: true),
    vatRate: _moneyOrNull(json, 'vat_rate'),
    grossAmount: _moneyOrNull(json, 'gross_amount'),
    netAmount: _moneyOrNull(json, 'net_amount'),
    vatableAmount: _moneyOrNull(json, 'vatable_amount'),
    vatAmount: _moneyOrNull(json, 'vat_amount'),
    serverTotalAmount: _moneyOrNull(json, 'total_amount'),
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
    discountAmount: discountAmount,
    vatInclusive: vatInclusive,
    vatRate: vatRate,
    grossAmount: grossAmount,
    netAmount: netAmount,
    vatableAmount: vatableAmount,
    vatAmount: vatAmount,
    serverTotalAmount: serverTotalAmount,
  );
}

/// A money field that a pre-B2 payload omits: read as 0, because the server's
/// own default for the discount is nothing off.
double _moneyOrZero(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return 0;
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null) {
    throw FormatException('Field "$key" is not a decimal: "$value"');
  }
  return parsed;
}

/// A money field whose ABSENCE is meaningful (a figure the server never sent),
/// so it stays null rather than becoming a zero nobody computed.
double? _moneyOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null) {
    throw FormatException('Field "$key" is not a decimal: "$value"');
  }
  return parsed;
}
