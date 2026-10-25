/// The two write payloads the product form submits.
///
/// They live in the data layer rather than in the dialog because they are the
/// exact shape the server accepts, and because the create path is a CHAIN of
/// three POSTs (product → variant → selling unit) driven by the repository, not
/// by a widget. Phase 4 Task 4.
class NewProductDraft {
  const NewProductDraft({
    required this.categoryId,
    required this.brandId,
    required this.baseName,
    required this.description,
    required this.imageUrl,
    required this.variantName,
    required this.baseUomId,
    required this.minStockThreshold,
    required this.maxStockLevel,
    required this.sellingPrice,
    this.barcodeQr = '',
  });

  final int categoryId;
  final int brandId;
  final String baseName;
  final String description;
  final String imageUrl;
  final String variantName;
  final int baseUomId;
  final double minStockThreshold;
  final double maxStockLevel;

  /// The factor-1 selling unit's price. The till charges this (decision 08).
  final double sellingPrice;

  /// Optional: the server defaults it to an empty string, and the seeded
  /// catalogue has no barcodes at all.
  final String barcodeQr;

  /// There is deliberately no quantity, cost or opening-batch field.
  ///
  /// User decision 2026-10-25: a product's first stock arrives through a
  /// purchase order the stock manager creates and then receives. "Add product"
  /// creates the catalog item only, so the form cannot invent stock the server
  /// never received.
  Map<String, dynamic> productBody() => {
    'category': categoryId,
    'brand': brandId,
    'base_name': baseName,
    'description': description,
    'image_url': imageUrl,
  };

  Map<String, dynamic> variantBody(int productId) => {
    'product': productId,
    'variant_name': variantName,
    'base_uom': baseUomId,
    'min_stock_threshold': minStockThreshold,
    'max_stock_level': maxStockLevel,
  };

  Map<String, dynamic> sellingUnitBody(int variantId, int uomId) => {
    'variant': variantId,
    'uom': uomId,
    'conversion_factor': 1,
    'default_selling_price': sellingPrice,
    'barcode_qr': barcodeQr,
  };
}

/// An edit of an existing product: name, description, category, brand,
/// threshold, max level, price and barcode, and the archive flag.
///
/// Every field is optional because each one is a separate PATCH target: the
/// price lives on the selling unit, the threshold on the variant and the rest on
/// the product, and sending a field the user did not touch would write a value
/// nobody asked for.
class ProductEditDraft {
  const ProductEditDraft({
    required this.productId,
    required this.variantId,
    required this.sellingUnitId,
    this.baseName,
    this.description,
    this.categoryId,
    this.brandId,
    this.variantName,
    this.minStockThreshold,
    this.maxStockLevel,
    this.sellingPrice,
    this.barcodeQr,
    this.isActive,
  });

  final int productId;
  final int variantId;

  /// 0 when the variant has no selling unit yet — a price cannot be PATCHed
  /// onto a row that does not exist, so the repository skips it.
  final int sellingUnitId;

  final String? baseName;
  final String? description;
  final int? categoryId;
  final int? brandId;
  final String? variantName;
  final double? minStockThreshold;
  final double? maxStockLevel;
  final double? sellingPrice;
  final String? barcodeQr;
  final bool? isActive;

  Map<String, dynamic> get productBody => {
    if (baseName != null) 'base_name': baseName,
    if (description != null) 'description': description,
    if (categoryId != null) 'category': categoryId,
    if (brandId != null) 'brand': brandId,
    if (isActive != null) 'is_active': isActive,
  };

  Map<String, dynamic> get variantBody => {
    if (variantName != null) 'variant_name': variantName,
    if (minStockThreshold != null) 'min_stock_threshold': minStockThreshold,
    if (maxStockLevel != null) 'max_stock_level': maxStockLevel,
  };

  /// `variant`, `uom` and `conversion_factor` are frozen once the unit has been
  /// sold (400 `SELLING_UNIT_IN_USE`), so a price edit must never resend them.
  Map<String, dynamic> get sellingUnitBody => {
    if (sellingPrice != null) 'default_selling_price': sellingPrice,
    if (barcodeQr != null) 'barcode_qr': barcodeQr,
  };
}
