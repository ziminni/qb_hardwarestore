import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/foundation.dart';

class PosTransactionViewmodel extends ChangeNotifier {
  PosTransactionViewmodel(this._inventory, this._tracking) {
    _inventory.addListener(_inventoryChanged);
    _tracking.addListener(_inventoryChanged);
  }

  final InventoryViewmodel _inventory;
  final ProductTrackingViewmodel _tracking;
  final List<PosCartLine> _lines = [];
  final List<PosReceipt> _receipts = [];
  String _query = '';

  List<PosCartLine> get lines => List.unmodifiable(_lines);
  List<PosReceipt> get receipts => List.unmodifiable(_receipts);
  double get subtotal => _lines.fold(0, (sum, line) => sum + line.total);
  double get total => subtotal;
  int get itemCount => _lines.length;

  List<PosCatalogItem> get _catalog {
    final items = <PosCatalogItem>[];
    for (final record in _inventory.stockRecords) {
      if (!record.product.isActive ||
          !record.variant.isActive ||
          record.variant.currentStock <= 0) {
        continue;
      }
      final tracking = _tracking.configurationFor(record.product.baseName);
      final usesTracking =
          tracking != null &&
          tracking.baseUnit.toLowerCase() ==
              record.variant.baseUomCode.toLowerCase();
      final units = <String>[
        if (usesTracking &&
            tracking.packageType.isNotEmpty &&
            (tracking.stockForm == ProductStockForm.packaged ||
                tracking.stockForm == ProductStockForm.standardLengths))
          tracking.packageType,
        if (usesTracking) ...tracking.allowedSaleUnits,
        if (!usesTracking) record.variant.baseUomCode,
      ];
      final distinctUnits = <String>[];
      for (final unit in units) {
        if (!distinctUnits.any(
          (existing) => existing.toLowerCase() == unit.toLowerCase(),
        )) {
          distinctUnits.add(unit);
        }
      }
      for (var index = 0; index < distinctUnits.length; index++) {
        final unit = distinctUnits[index];
        final factor = usesTracking ? _conversionFactor(tracking, unit) : 1.0;
        final configuredPackagePrice =
            usesTracking &&
                unit.toLowerCase() == tracking.packageType.toLowerCase()
            ? tracking.packageSellingPrice
            : 0.0;
        items.add(
          PosCatalogItem(
            variantUomId: record.variant.id * 100 + index,
            variantId: record.variant.id,
            productName: record.product.baseName,
            variantName: record.variant.variantName,
            unit: unit,
            barcode: record.variant.qrIdentifier.isNotEmpty
                ? record.variant.qrIdentifier
                : record.variant.sku,
            conversionFactor: factor,
            unitPrice: configuredPackagePrice > 0
                ? configuredPackagePrice
                : record.variant.sellingPrice * factor,
            availableBaseStock: record.variant.currentStock,
          ),
        );
      }
    }
    return items;
  }

  List<PosCatalogItem> get filteredProducts {
    final matched = _query.isEmpty
        ? _catalog
        : _catalog
              .where(
                (item) =>
                    item.productName.toLowerCase().contains(_query) ||
                    item.variantName.toLowerCase().contains(_query) ||
                    item.barcode.toLowerCase().contains(_query) ||
                    item.unit.toLowerCase().contains(_query),
              )
              .toList(growable: false);
    final variants = <int, PosCatalogItem>{};
    for (final item in matched) {
      variants.putIfAbsent(item.variantId, () => item);
    }
    return variants.values.toList(growable: false);
  }

  List<PosCatalogItem> saleOptionsFor(PosCatalogItem product) => _catalog
      .where((item) => item.variantId == product.variantId)
      .toList(growable: false);

  PosCatalogItem? findByBarcode(String value) {
    final barcode = value.trim().toLowerCase();
    if (barcode.isEmpty) return null;
    for (final item in _catalog) {
      if (item.barcode.trim().toLowerCase() == barcode) return item;
    }
    return null;
  }

  void setQuery(String value) {
    _query = value.trim().toLowerCase();
    notifyListeners();
  }

  void _inventoryChanged() => notifyListeners();

  @override
  void dispose() {
    _inventory.removeListener(_inventoryChanged);
    _tracking.removeListener(_inventoryChanged);
    super.dispose();
  }

  String? addLine(PosCatalogItem item, double quantity) {
    if (quantity <= 0) return 'Enter a quantity greater than zero.';
    final index = _lines.indexWhere(
      (line) => line.variantUomId == item.variantUomId,
    );
    final cartQuantity = index < 0 ? 0.0 : _lines[index].quantity;
    final reservedBaseStock = _lines
        .where((line) {
          final option = _catalog.firstWhere(
            (catalogItem) => catalogItem.variantUomId == line.variantUomId,
          );
          return option.variantId == item.variantId;
        })
        .fold<double>(0, (sum, line) {
          final option = _catalog.firstWhere(
            (catalogItem) => catalogItem.variantUomId == line.variantUomId,
          );
          return sum + line.quantity * option.conversionFactor;
        });
    final requestedBaseStock = quantity * item.conversionFactor;
    if (reservedBaseStock + requestedBaseStock > item.availableBaseStock) {
      return 'Only ${_quantity(item.availableSaleQuantity)} ${item.unit} available.';
    }
    if (index < 0) {
      _lines.add(
        PosCartLine(
          variantUomId: item.variantUomId,
          productName: item.productName,
          variantName: item.variantName,
          quantity: quantity,
          unit: item.unit,
          unitPrice: item.unitPrice,
          availableQuantity: item.availableSaleQuantity,
        ),
      );
    } else {
      _lines[index] = _lines[index].copyWith(quantity: cartQuantity + quantity);
    }
    notifyListeners();
    return null;
  }

  void removeLine(int index) {
    _lines.removeAt(index);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  String? validate() {
    if (_lines.isEmpty) return 'Add at least one product to the transaction.';
    final requestedByVariant = <int, double>{};
    for (final line in _lines) {
      final item = _catalog.firstWhere(
        (catalogItem) => catalogItem.variantUomId == line.variantUomId,
      );
      requestedByVariant[item.variantId] =
          (requestedByVariant[item.variantId] ?? 0) +
          line.quantity * item.conversionFactor;
      if (requestedByVariant[item.variantId]! > item.availableBaseStock) {
        return '${line.productName}: the combined units exceed available stock.';
      }
    }
    return null;
  }

  PosReceipt complete({
    required String paymentMethod,
    required double amountPaid,
  }) {
    final now = DateTime.now();
    final suffix = now.millisecondsSinceEpoch.toString().substring(5);
    final reference = 'SIM-$suffix';
    for (final line in _lines) {
      final index = _catalog.indexWhere(
        (item) => item.variantUomId == line.variantUomId,
      );
      final item = _catalog[index];
      final deductedBaseStock = line.quantity * item.conversionFactor;
      _inventory.sellStock(
        variantId: item.variantId,
        quantity: deductedBaseStock,
        reference: reference,
        userName: 'POS Staff',
      );
    }
    final receipt = PosReceipt(
      reference: reference,
      officialReceiptNumber: 'SIM-OR-$suffix',
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

  String _quantity(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  double _conversionFactor(ProductTrackingConfiguration tracking, String unit) {
    if (unit.toLowerCase() == tracking.packageType.toLowerCase()) {
      return tracking.stockForm == ProductStockForm.standardLengths
          ? tracking.standardLength
          : tracking.packageSize;
    }
    const factors = {
      'g': .001,
      'kg': 1.0,
      'mm': .001,
      'cm': .01,
      'meter': 1.0,
      'm': 1.0,
      'inch': .0254,
      'foot': .3048,
      'ml': .001,
      'l': 1.0,
      'piece': 1.0,
    };
    final from = factors[unit.toLowerCase()] ?? 1;
    final base = factors[tracking.baseUnit.toLowerCase()] ?? 1;
    return from / base;
  }
}
