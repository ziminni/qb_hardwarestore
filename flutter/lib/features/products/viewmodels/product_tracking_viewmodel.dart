import 'dart:math';
import 'package:client/data/models/product_tracking.dart';
import 'package:flutter/foundation.dart';

class ProductTrackingViewmodel extends ChangeNotifier {
  ProductTrackingViewmodel() {
    _seed();
  }
  final Map<String, ProductTrackingConfiguration> _configurations = {};
  List<ProductTrackingConfiguration> get configurations =>
      List.unmodifiable(_configurations.values);
  ProductTrackingConfiguration? configurationFor(String name) =>
      _configurations[name.toLowerCase()];
  void save(ProductTrackingConfiguration value) {
    _configurations[value.productName.toLowerCase()] = value;
    notifyListeners();
  }

  InventorySimulationResult validateSale(
    String productName,
    double quantity,
    String unit,
  ) {
    final config = configurationFor(productName);
    if (config == null) {
      return const InventorySimulationResult(
        success: false,
        message: 'Tracking configuration not found.',
      );
    }
    if (quantity <= 0) {
      return const InventorySimulationResult(
        success: false,
        message: 'Enter a quantity greater than zero.',
      );
    }
    if (!config.allowedSaleUnits.contains(unit)) {
      return const InventorySimulationResult(
        success: false,
        message: 'The selected sale unit is not supported.',
      );
    }
    if (config.method == ProductTrackingMethod.quantity &&
        !config.allowFractional &&
        quantity != quantity.roundToDouble()) {
      return const InventorySimulationResult(
        success: false,
        message: 'Fractional quantities are not allowed for this product.',
      );
    }
    final baseQuantity = _convert(quantity, unit, config.baseUnit);
    if (config.method == ProductTrackingMethod.length &&
        config.stockForm == ProductStockForm.standardLengths &&
        !config.physicalPieces.any((piece) => piece >= baseQuantity)) {
      return const InventorySimulationResult(
        success: false,
        message: 'No single piece is long enough. Remnants cannot be combined.',
      );
    }
    if (baseQuantity > config.totalBaseQuantity) {
      return const InventorySimulationResult(
        success: false,
        message: 'Not enough inventory for this mock sale.',
      );
    }
    return const InventorySimulationResult(
      success: true,
      message: 'Inventory is available.',
    );
  }

  InventorySimulationResult simulateSale(
    String productName,
    double quantity,
    String unit,
  ) {
    final validation = validateSale(productName, quantity, unit);
    if (!validation.success) return validation;
    final key = productName.toLowerCase();
    final config = _configurations[key];
    if (config == null) return validation;
    final baseQuantity = _convert(quantity, unit, config.baseUnit);
    if (config.method == ProductTrackingMethod.length &&
        config.stockForm == ProductStockForm.standardLengths) {
      return _cutLength(key, config, baseQuantity);
    }
    if (baseQuantity > config.totalBaseQuantity) {
      return const InventorySimulationResult(
        success: false,
        message: 'Not enough inventory for this mock sale.',
      );
    }
    if (config.stockForm == ProductStockForm.packaged &&
        config.allowPartialPackage) {
      var remainder = config.openPackageRemainder;
      var needed = baseQuantity;
      if (remainder > 0) {
        final used = min(remainder, needed);
        remainder -= used;
        needed -= used;
      }
      if (needed > 0) {
        final packagesOpened = (needed / config.packageSize).ceil();
        remainder = packagesOpened * config.packageSize - needed;
      }
      final updated = config.copyWith(
        totalBaseQuantity: config.totalBaseQuantity - baseQuantity,
        openPackageRemainder: remainder,
      );
      _configurations[key] = updated;
      notifyListeners();
      return InventorySimulationResult(
        success: true,
        message:
            '${updated.sealedPackages} sealed ${config.packageType.toLowerCase()}s, ${remainder.toStringAsFixed(2)} ${config.baseUnit} opened remainder, ${updated.totalBaseQuantity.toStringAsFixed(2)} ${config.baseUnit} total.',
      );
    }
    _configurations[key] = config.copyWith(
      totalBaseQuantity: config.totalBaseQuantity - baseQuantity,
    );
    notifyListeners();
    return InventorySimulationResult(
      success: true,
      message:
          'Remaining inventory: ${(config.totalBaseQuantity - baseQuantity).toStringAsFixed(2)} ${config.baseUnit}.',
    );
  }

  InventorySimulationResult _cutLength(
    String key,
    ProductTrackingConfiguration config,
    double requested,
  ) {
    final pieces = List<double>.of(config.physicalPieces);
    final candidates = [
      for (var i = 0; i < pieces.length; i++)
        if (pieces[i] >= requested) i,
    ]..sort((a, b) => pieces[a].compareTo(pieces[b]));
    if (candidates.isEmpty) {
      return const InventorySimulationResult(
        success: false,
        message: 'No single piece is long enough. Remnants cannot be combined.',
      );
    }
    final index = candidates.first;
    pieces[index] -= requested;
    if (pieces[index] <= 0.0001) {
      pieces.removeAt(index);
    }
    final updated = config.copyWith(
      totalBaseQuantity: config.totalBaseQuantity - requested,
      physicalPieces: pieces,
    );
    _configurations[key] = updated;
    notifyListeners();
    return InventorySimulationResult(
      success: true,
      message:
          '${updated.fullPieces} full pieces, ${updated.cutPieces} cut piece(s), ${updated.totalBaseQuantity.toStringAsFixed(3)} ${config.baseUnit} total.',
    );
  }

  double _convert(double value, String from, String to) {
    if (from == to) return value;
    const toMeters = {
      'mm': .001,
      'cm': .01,
      'meter': 1.0,
      'm': 1.0,
      'inch': .0254,
      'foot': .3048,
    };
    const toKg = {'g': .001, 'kg': 1.0};
    const toLiter = {'mL': .001, 'L': 1.0};
    if (toMeters.containsKey(from) && toMeters.containsKey(to)) {
      return value * toMeters[from]! / toMeters[to]!;
    }
    if (toKg.containsKey(from) && toKg.containsKey(to)) {
      return value * toKg[from]! / toKg[to]!;
    }
    if (toLiter.containsKey(from) && toLiter.containsKey(to)) {
      return value * toLiter[from]! / toLiter[to]!;
    }
    return value;
  }

  void _seed() {
    save(
      const ProductTrackingConfiguration(
        productName: 'Claw Hammer',
        method: ProductTrackingMethod.quantity,
        baseUnit: 'piece',
        stockForm: ProductStockForm.direct,
        allowFractional: false,
        allowPartialPackage: false,
        packageType: '',
        packageSize: 0,
        initialPackages: 0,
        totalBaseQuantity: 20,
        reorderLevel: 6,
        storageLocation: 'Shelf G-02',
        costPrice: 280,
        sellingPrice: 350,
        packageSellingPrice: 0,
        standardLength: 0,
        allowedSaleUnits: ['piece'],
        physicalPieces: [],
      ),
    );
    save(
      const ProductTrackingConfiguration(
        productName: 'Portland Cement',
        method: ProductTrackingMethod.weight,
        baseUnit: 'kg',
        stockForm: ProductStockForm.packaged,
        allowFractional: true,
        allowPartialPackage: true,
        packageType: 'Bag',
        packageSize: 40,
        initialPackages: 100,
        totalBaseQuantity: 4000,
        reorderLevel: 1200,
        storageLocation: 'Rack A-01',
        costPrice: 235,
        sellingPrice: 7,
        packageSellingPrice: 270,
        standardLength: 0,
        allowedSaleUnits: ['kg', 'g'],
        physicalPieces: [],
      ),
    );
    save(
      const ProductTrackingConfiguration(
        productName: 'Common Nail',
        method: ProductTrackingMethod.weight,
        baseUnit: 'kg',
        stockForm: ProductStockForm.direct,
        allowFractional: true,
        allowPartialPackage: false,
        packageType: '',
        packageSize: 0,
        initialPackages: 0,
        totalBaseQuantity: 125,
        reorderLevel: 20,
        storageLocation: 'Bin H-01',
        costPrice: 72,
        sellingPrice: 95,
        packageSellingPrice: 0,
        standardLength: 0,
        allowedSaleUnits: ['kg', 'g'],
        physicalPieces: [],
      ),
    );
    save(
      ProductTrackingConfiguration(
        productName: 'PVC Pipe',
        method: ProductTrackingMethod.length,
        baseUnit: 'meter',
        stockForm: ProductStockForm.standardLengths,
        allowFractional: true,
        allowPartialPackage: true,
        packageType: 'Piece',
        packageSize: 10,
        initialPackages: 10,
        totalBaseQuantity: 100,
        reorderLevel: 20,
        storageLocation: 'Pipe Rack A-02',
        costPrice: 800,
        sellingPrice: 110,
        packageSellingPrice: 1000,
        standardLength: 10,
        allowedSaleUnits: const ['meter', 'cm', 'mm', 'inch', 'foot'],
        physicalPieces: List.filled(10, 10),
      ),
    );
    save(
      const ProductTrackingConfiguration(
        productName: 'Electrical Wire',
        method: ProductTrackingMethod.length,
        baseUnit: 'meter',
        stockForm: ProductStockForm.continuous,
        allowFractional: true,
        allowPartialPackage: true,
        packageType: 'Roll',
        packageSize: 150,
        initialPackages: 1,
        totalBaseQuantity: 150,
        reorderLevel: 30,
        storageLocation: 'Rack D-05',
        costPrice: 14,
        sellingPrice: 18,
        packageSellingPrice: 2490,
        standardLength: 0,
        allowedSaleUnits: ['meter', 'cm', 'foot'],
        physicalPieces: [],
      ),
    );
    save(
      const ProductTrackingConfiguration(
        productName: 'Waterproofing Liquid',
        method: ProductTrackingMethod.volume,
        baseUnit: 'L',
        stockForm: ProductStockForm.packaged,
        allowFractional: true,
        allowPartialPackage: true,
        packageType: 'Container',
        packageSize: 4,
        initialPackages: 20,
        totalBaseQuantity: 80,
        reorderLevel: 16,
        storageLocation: 'Shelf I-01',
        costPrice: 150,
        sellingPrice: 55,
        packageSellingPrice: 220,
        standardLength: 0,
        allowedSaleUnits: ['L', 'mL'],
        physicalPieces: [],
      ),
    );
  }
}
