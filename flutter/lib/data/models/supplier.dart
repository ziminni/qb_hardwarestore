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
}

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
}
