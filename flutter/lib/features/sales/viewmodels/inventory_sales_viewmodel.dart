import 'package:client/data/models/sales.dart';
import 'package:flutter/foundation.dart';

class InventorySalesViewmodel extends ChangeNotifier {
  final List<InventorySale> _sales = [
    InventorySale(
      transactionNo: 'TRX-20260915-0061',
      date: DateTime(2026, 9, 15, 15, 22),
      customer: 'Walk-in Customer',
      cashier: 'POS Staff',
      paymentMethod: 'Cash',
      source: 'Walk-in',
      status: InventorySaleStatus.completed,
      lines: const [
        InventorySaleLine(
          productName: 'Portland Cement',
          variantName: '40 kg Bag',
          sku: 'CEM-HOL-40',
          quantity: 10,
          unitPrice: 270,
        ),
        InventorySaleLine(
          productName: 'Common Nail',
          variantName: '2 inch × 1 kg',
          sku: 'NAIL-COM-02',
          quantity: 2,
          unitPrice: 95,
        ),
      ],
    ),
    InventorySale(
      transactionNo: 'TRX-20260915-0060',
      date: DateTime(2026, 9, 15, 13, 5),
      customer: 'JDL Construction',
      cashier: 'POS Staff',
      paymentMethod: 'Bank Transfer',
      source: 'Requisition',
      status: InventorySaleStatus.completed,
      lines: const [
        InventorySaleLine(
          productName: 'Deformed Steel Bar',
          variantName: '12 mm × 6 m',
          sku: 'BAR-SA-12',
          quantity: 20,
          unitPrice: 260,
        ),
      ],
    ),
    InventorySale(
      transactionNo: 'TRX-20260915-0059',
      date: DateTime(2026, 9, 15, 10, 44),
      customer: 'Walk-in Customer',
      cashier: 'POS Staff',
      paymentMethod: 'GCash',
      source: 'Walk-in',
      status: InventorySaleStatus.refunded,
      lines: const [
        InventorySaleLine(
          productName: 'Claw Hammer',
          variantName: '16 oz',
          sku: 'HAM-STA-16',
          quantity: 1,
          unitPrice: 525,
        ),
      ],
    ),
    InventorySale(
      transactionNo: 'TRX-20260914-0058',
      date: DateTime(2026, 9, 14, 16, 30),
      customer: 'Ramos Builders',
      cashier: 'POS Staff',
      paymentMethod: 'Cash',
      source: 'Walk-in',
      status: InventorySaleStatus.completed,
      lines: const [
        InventorySaleLine(
          productName: 'PVC Pipe',
          variantName: '1 inch × 3 m',
          sku: 'PVC-NEL-100',
          quantity: 6,
          unitPrice: 290,
        ),
      ],
    ),
    InventorySale(
      transactionNo: 'TRX-20260914-0057',
      date: DateTime(2026, 9, 14, 11, 12),
      customer: 'Walk-in Customer',
      cashier: 'POS Staff',
      paymentMethod: 'Card',
      source: 'Walk-in',
      status: InventorySaleStatus.voided,
      lines: const [
        InventorySaleLine(
          productName: 'Convenience Outlet',
          variantName: 'Universal Duplex',
          sku: 'OUT-ROY-UNI',
          quantity: 3,
          unitPrice: 135,
        ),
      ],
    ),
  ];
  final List<InventoryReturn> _returns = [
    InventoryReturn(
      reference: 'RET-0012',
      date: DateTime(2026, 9, 15, 11, 5),
      type: InventoryReturnType.customer,
      relatedReference: 'TRX-20260915-0059',
      productName: 'Claw Hammer',
      variantName: '16 oz',
      sku: 'HAM-STA-16',
      quantity: 1,
      reason: 'Manufacturing defect',
      status: InventoryReturnStatus.completed,
      processedBy: 'Inventory Staff',
    ),
    InventoryReturn(
      reference: 'RET-0011',
      date: DateTime(2026, 9, 14, 14, 18),
      type: InventoryReturnType.supplier,
      relatedReference: 'PO-1007',
      productName: 'PVC Elbow',
      variantName: '1 inch',
      sku: 'ELB-NEL-100',
      quantity: 3,
      reason: 'Cracked on delivery',
      status: InventoryReturnStatus.approved,
      processedBy: 'Inventory Staff',
    ),
    InventoryReturn(
      reference: 'RET-0010',
      date: DateTime(2026, 9, 13, 9, 20),
      type: InventoryReturnType.customer,
      relatedReference: 'TRX-20260912-0052',
      productName: 'Electrical Wire',
      variantName: '3.5 mm² × 150 m',
      sku: 'WIR-PD-350',
      quantity: 1,
      reason: 'Wrong specification',
      status: InventoryReturnStatus.pending,
      processedBy: 'Inventory Staff',
    ),
  ];
  List<InventorySale> get sales => List.unmodifiable(_sales);
  List<InventoryReturn> get returns => List.unmodifiable(_returns);
  double get completedRevenue => _sales
      .where((sale) => sale.status == InventorySaleStatus.completed)
      .fold(0, (sum, sale) => sum + sale.total);
  double get soldUnits => _sales
      .where((sale) => sale.status == InventorySaleStatus.completed)
      .fold(0, (sum, sale) => sum + sale.totalQuantity);
  int get completedReturns => _returns
      .where((item) => item.status == InventoryReturnStatus.completed)
      .length;
  void addReturn(InventoryReturn value) {
    _returns.insert(0, value);
    notifyListeners();
  }
}
