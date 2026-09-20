import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/foundation.dart';

class PosTransactionViewmodel extends ChangeNotifier {
  final List<PosCartLine> _lines = [];
  final List<PosReceipt> _receipts = [];
  String _query = '';

  List<PosCartLine> get lines => List.unmodifiable(_lines);
  List<PosReceipt> get receipts => List.unmodifiable(_receipts);
  String get query => _query;
  double get subtotal => _lines.fold(0, (sum, line) => sum + line.total);
  double get total => subtotal;
  int get itemCount => _lines.length;

  void setQuery(String value) {
    _query = value.trim().toLowerCase();
    notifyListeners();
  }

  List<ProductTrackingConfiguration> filteredProducts(
    List<ProductTrackingConfiguration> products,
  ) => _query.isEmpty
      ? products
      : products
            .where(
              (product) =>
                  product.productName.toLowerCase().contains(_query) ||
                  product.method.label.toLowerCase().contains(_query),
            )
            .toList();

  void addLine(
    ProductTrackingConfiguration product,
    double quantity,
    String unit,
  ) {
    final index = _lines.indexWhere(
      (line) => line.productName == product.productName && line.unit == unit,
    );
    final price = _priceFor(product, unit);
    if (index < 0) {
      _lines.add(
        PosCartLine(
          productName: product.productName,
          quantity: quantity,
          unit: unit,
          unitPrice: price,
        ),
      );
    } else {
      _lines[index] = _lines[index].copyWith(
        quantity: _lines[index].quantity + quantity,
      );
    }
    notifyListeners();
  }

  void removeLine(int index) {
    _lines.removeAt(index);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  InventorySimulationResult validate(ProductTrackingViewmodel inventory) {
    if (_lines.isEmpty) {
      return const InventorySimulationResult(
        success: false,
        message: 'Add at least one product to the transaction.',
      );
    }
    for (final line in _lines) {
      final result = inventory.validateSale(
        line.productName,
        line.quantity,
        line.unit,
      );
      if (!result.success) {
        return InventorySimulationResult(
          success: false,
          message: '${line.productName}: ${result.message}',
        );
      }
    }
    return const InventorySimulationResult(
      success: true,
      message: 'Transaction is ready.',
    );
  }

  PosReceipt complete({
    required ProductTrackingViewmodel inventory,
    required String paymentMethod,
    required double amountPaid,
  }) {
    for (final line in _lines) {
      inventory.simulateSale(line.productName, line.quantity, line.unit);
    }
    final now = DateTime.now();
    final receipt = PosReceipt(
      reference: 'QB-${now.millisecondsSinceEpoch.toString().substring(5)}',
      createdAt: now,
      lines: List.unmodifiable(_lines),
      paymentMethod: paymentMethod,
      amountPaid: amountPaid,
      total: total,
    );
    _receipts.insert(0, receipt);
    _lines.clear();
    notifyListeners();
    return receipt;
  }

  double _priceFor(ProductTrackingConfiguration product, String unit) {
    const conversionToBase = {
      'g': .001,
      'kg': 1.0,
      'mm': .001,
      'cm': .01,
      'meter': 1.0,
      'm': 1.0,
      'inch': .0254,
      'foot': .3048,
      'mL': .001,
      'L': 1.0,
      'piece': 1.0,
    };
    return product.sellingPrice * (conversionToBase[unit] ?? 1);
  }
}
