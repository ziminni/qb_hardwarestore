enum ProductTrackingMethod {
  quantity('By Quantity', 'Items counted individually'),
  weight('By Weight', 'Materials measured by weight'),
  length('By Length', 'Materials measured or cut by length'),
  volume('By Volume', 'Materials measured by liquid volume');

  const ProductTrackingMethod(this.label, this.description);
  final String label;
  final String description;
}

enum ProductStockForm {
  direct('Bulk / Measured'),
  packaged('Packaged'),
  continuous('Continuous / Measured Length'),
  standardLengths('Individual Standard Lengths');

  const ProductStockForm(this.label);
  final String label;
}

class ProductTrackingConfiguration {
  const ProductTrackingConfiguration({
    required this.productName,
    required this.method,
    required this.baseUnit,
    required this.stockForm,
    required this.allowFractional,
    required this.allowPartialPackage,
    required this.packageType,
    required this.packageSize,
    required this.initialPackages,
    required this.totalBaseQuantity,
    required this.reorderLevel,
    required this.storageLocation,
    required this.costPrice,
    required this.sellingPrice,
    required this.packageSellingPrice,
    required this.standardLength,
    required this.allowedSaleUnits,
    required this.physicalPieces,
    this.openPackageRemainder = 0,
  });

  final String productName;
  final ProductTrackingMethod method;
  final String baseUnit;
  final ProductStockForm stockForm;
  final bool allowFractional;
  final bool allowPartialPackage;
  final String packageType;
  final double packageSize;
  final int initialPackages;
  final double totalBaseQuantity;
  final double reorderLevel;
  final String storageLocation;
  final double costPrice;
  final double sellingPrice;
  final double packageSellingPrice;
  final double standardLength;
  final List<String> allowedSaleUnits;
  final List<double> physicalPieces;
  final double openPackageRemainder;

  int get sealedPackages => packageSize <= 0
      ? 0
      : ((totalBaseQuantity - openPackageRemainder) / packageSize).floor();
  int get fullPieces => physicalPieces
      .where((piece) => (piece - standardLength).abs() < 0.0001)
      .length;
  int get cutPieces => physicalPieces.length - fullPieces;

  ProductTrackingConfiguration copyWith({
    String? productName,
    double? totalBaseQuantity,
    List<double>? physicalPieces,
    double? openPackageRemainder,
  }) {
    return ProductTrackingConfiguration(
      productName: productName ?? this.productName,
      method: method,
      baseUnit: baseUnit,
      stockForm: stockForm,
      allowFractional: allowFractional,
      allowPartialPackage: allowPartialPackage,
      packageType: packageType,
      packageSize: packageSize,
      initialPackages: initialPackages,
      totalBaseQuantity: totalBaseQuantity ?? this.totalBaseQuantity,
      reorderLevel: reorderLevel,
      storageLocation: storageLocation,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      packageSellingPrice: packageSellingPrice,
      standardLength: standardLength,
      allowedSaleUnits: allowedSaleUnits,
      physicalPieces: physicalPieces ?? this.physicalPieces,
      openPackageRemainder: openPackageRemainder ?? this.openPackageRemainder,
    );
  }
}

class InventorySimulationResult {
  const InventorySimulationResult({
    required this.success,
    required this.message,
  });
  final bool success;
  final String message;
}
