import 'dart:math';
import 'package:client/data/models/supplier.dart';
import 'package:flutter/foundation.dart';

class SuppliersPurchasesViewmodel extends ChangeNotifier {
  final List<Supplier> _suppliers = [
    const Supplier(
      id: 1,
      companyName: 'Cebu Oversea Hardware Co.',
      contactPerson: 'Maria Santos',
      phone: '0917 812 4401',
      email: 'orders@cebuoversea.ph',
      address: 'Mandaue City, Cebu',
    ),
    const Supplier(
      id: 2,
      companyName: 'Philcement Trading',
      contactPerson: 'Ramon Cruz',
      phone: '0918 225 1034',
      email: 'sales@philcement.ph',
      address: 'Talisay City, Cebu',
    ),
    const Supplier(
      id: 3,
      companyName: 'Neltex Distribution Cebu',
      contactPerson: 'Janine Lim',
      phone: '0917 330 8821',
      email: 'cebu@neltex.com.ph',
      address: 'Consolacion, Cebu',
    ),
    const Supplier(
      id: 4,
      companyName: 'VisMin Steel Supply',
      contactPerson: 'Eduardo Tan',
      phone: '0920 445 7720',
      email: 'orders@visminsteel.ph',
      address: 'Lapu-Lapu City, Cebu',
    ),
    const Supplier(
      id: 5,
      companyName: 'Metro Electrical Depot',
      contactPerson: 'Angela Uy',
      phone: '0916 780 2255',
      email: 'sales@metroelectrical.ph',
      address: 'Cebu City, Cebu',
    ),
    const Supplier(
      id: 6,
      companyName: 'Builders Wood Centre',
      contactPerson: 'Carlo Reyes',
      phone: '0919 622 1188',
      email: 'supply@builderswood.ph',
      address: 'Minglanilla, Cebu',
    ),
  ];
  final List<PurchaseOrder> _purchases = [
    PurchaseOrder(
      id: 1008,
      supplierId: 1,
      supplierName: 'Cebu Oversea Hardware Co.',
      orderDate: DateTime(2026, 9, 12),
      expectedDelivery: DateTime(2026, 9, 17),
      status: PurchaseStatus.ordered,
      createdBy: 'Inventory Staff',
      notes: 'Regular replenishment',
      items: const [
        PurchaseItem(
          productName: 'Common Nail',
          variantName: '2 inch × 1 kg',
          sku: 'NAIL-COM-02',
          quantity: 40,
          receivedQuantity: 0,
          unitCost: 72,
        ),
      ],
    ),
    PurchaseOrder(
      id: 1007,
      supplierId: 3,
      supplierName: 'Neltex Distribution Cebu',
      orderDate: DateTime(2026, 9, 11),
      expectedDelivery: DateTime(2026, 9, 15),
      status: PurchaseStatus.partial,
      createdBy: 'Inventory Staff',
      notes: 'Urgent PVC restock',
      items: const [
        PurchaseItem(
          productName: 'PVC Pipe',
          variantName: '1 inch × 3 m',
          sku: 'PVC-NEL-100',
          quantity: 50,
          receivedQuantity: 25,
          unitCost: 230,
        ),
        PurchaseItem(
          productName: 'PVC Elbow',
          variantName: '1 inch',
          sku: 'ELB-NEL-100',
          quantity: 40,
          receivedQuantity: 20,
          unitCost: 32,
        ),
      ],
    ),
    PurchaseOrder(
      id: 1006,
      supplierId: 4,
      supplierName: 'VisMin Steel Supply',
      orderDate: DateTime(2026, 9, 9),
      expectedDelivery: DateTime(2026, 9, 13),
      status: PurchaseStatus.complete,
      createdBy: 'Admin',
      notes: '',
      items: const [
        PurchaseItem(
          productName: 'Deformed Steel Bar',
          variantName: '12 mm × 6 m',
          sku: 'BAR-SA-12',
          quantity: 100,
          receivedQuantity: 100,
          unitCost: 220,
        ),
      ],
    ),
    PurchaseOrder(
      id: 1005,
      supplierId: 2,
      supplierName: 'Philcement Trading',
      orderDate: DateTime(2026, 9, 8),
      expectedDelivery: DateTime(2026, 9, 12),
      status: PurchaseStatus.complete,
      createdBy: 'Admin',
      notes: 'Monthly cement order',
      items: const [
        PurchaseItem(
          productName: 'Portland Cement',
          variantName: '40 kg Bag',
          sku: 'CEM-HOL-40',
          quantity: 150,
          receivedQuantity: 150,
          unitCost: 235,
        ),
      ],
    ),
    PurchaseOrder(
      id: 1004,
      supplierId: 5,
      supplierName: 'Metro Electrical Depot',
      orderDate: DateTime(2026, 9, 7),
      expectedDelivery: DateTime(2026, 9, 14),
      status: PurchaseStatus.draft,
      createdBy: 'Inventory Staff',
      notes: 'For approval',
      items: const [
        PurchaseItem(
          productName: 'Electrical Wire',
          variantName: '3.5 mm² × 150 m',
          sku: 'WIR-PD-350',
          quantity: 10,
          receivedQuantity: 0,
          unitCost: 3400,
        ),
      ],
    ),
  ];
  List<Supplier> get suppliers => List.unmodifiable(_suppliers);
  List<PurchaseOrder> get purchases => List.unmodifiable(_purchases);
  int get activeSuppliers => _suppliers.where((item) => item.isActive).length;
  double get openPurchaseValue => _purchases
      .where(
        (item) =>
            item.status == PurchaseStatus.draft ||
            item.status == PurchaseStatus.ordered ||
            item.status == PurchaseStatus.partial,
      )
      .fold(0, (sum, item) => sum + item.total);
  void saveSupplier(Supplier supplier) {
    final index = _suppliers.indexWhere((item) => item.id == supplier.id);
    if (index < 0) {
      final id =
          _suppliers.fold<int>(0, (value, item) => max(value, item.id)) + 1;
      _suppliers.add(
        Supplier(
          id: id,
          companyName: supplier.companyName,
          contactPerson: supplier.contactPerson,
          phone: supplier.phone,
          email: supplier.email,
          address: supplier.address,
        ),
      );
    } else {
      _suppliers[index] = supplier;
    }
    notifyListeners();
  }

  void toggleSupplier(Supplier supplier) {
    final index = _suppliers.indexWhere((item) => item.id == supplier.id);
    if (index < 0) return;
    _suppliers[index] = supplier.copyWith(isActive: !supplier.isActive);
    notifyListeners();
  }

  void addPurchase(PurchaseOrder order) {
    final id =
        _purchases.fold<int>(1000, (value, item) => max(value, item.id)) + 1;
    _purchases.insert(
      0,
      PurchaseOrder(
        id: id,
        supplierId: order.supplierId,
        supplierName: order.supplierName,
        orderDate: DateTime.now(),
        expectedDelivery: order.expectedDelivery,
        status: PurchaseStatus.draft,
        createdBy: order.createdBy,
        notes: order.notes,
        items: order.items,
      ),
    );
    notifyListeners();
  }
}
