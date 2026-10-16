import 'package:client/data/models/json_field.dart';
import 'package:client/data/models/variant_uom.dart';

class ProductVariant {
  const ProductVariant({
    required this.id,
    // --- API-faithful fields (added by the staged swap, decreed by R8) ---
    required this.productId,
    required this.baseUomId,
    required this.minStockThreshold,
    required this.maxStockLevel,
    this.sellingUoms = const [],
    // --- legacy flattened fields, DELETED in step 4 once the 13 readers migrate ---
    required this.variantName,
    required this.baseUomCode,
    required this.isActive,
    this.sku = '',
    this.qrIdentifier = '',
    this.costPrice = 0,
    this.sellingPrice = 0,
    this.currentStock = 0,
    this.storageLocation = '',
  });

  final int id;

  /// Owning product id. API field `product`.
  final int productId;

  /// Base unit id. API field `base_uom`.
  final int baseUomId;

  /// Low-stock threshold. API field `min_stock_threshold`; replaces `reorderLevel`.
  final double minStockThreshold;
  final double maxStockLevel;

  /// Selling units, each owning the charged price. API field `selling_uoms`.
  final List<VariantUom> sellingUoms;

  final String variantName;
  final String baseUomCode;
  final bool isActive;
  final String sku;
  final String qrIdentifier;
  final double costPrice;
  final double sellingPrice;
  final double currentStock;

  /// Legacy alias. `min_stock_threshold` is the API field; this getter keeps
  /// the old readers compiling until step 4 of the staged swap deletes it.
  double get reorderLevel => minStockThreshold;
  final String storageLocation;

  ProductVariant copyWith({
    bool? isActive,
    String? variantName,
    String? baseUomCode,
    String? sku,
    String? qrIdentifier,
    double? costPrice,
    double? sellingPrice,
    double? currentStock,
    String? storageLocation,
  }) {
    return ProductVariant(
      id: id,
      productId: productId,
      baseUomId: baseUomId,
      minStockThreshold: minStockThreshold,
      maxStockLevel: maxStockLevel,
      sellingUoms: sellingUoms,
      variantName: variantName ?? this.variantName,
      baseUomCode: baseUomCode ?? this.baseUomCode,
      isActive: isActive ?? this.isActive,
      sku: sku ?? this.sku,
      qrIdentifier: qrIdentifier ?? this.qrIdentifier,
      costPrice: costPrice ?? this.costPrice,
      sellingPrice: sellingPrice ?? this.sellingPrice,
      currentStock: currentStock ?? this.currentStock,
      storageLocation: storageLocation ?? this.storageLocation,
    );
  }

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: intField(json, 'id'),
      variantName: stringField(json, 'variant_name'),
      baseUomCode: stringField(json, 'base_uom_code'),
      isActive: boolFieldOr(json, 'is_active', or: true),
      productId: intField(json, 'product'),
      baseUomId: intField(json, 'base_uom'),
      minStockThreshold: decimalField(json, 'min_stock_threshold'),
      maxStockLevel: decimalField(json, 'max_stock_level'),
      sellingUoms: (json['selling_uoms'] as List<dynamic>? ?? const [])
          .map((u) => VariantUom.fromJson(u as Map<String, dynamic>))
          .toList(growable: false),
      sku: json['sku'] as String? ?? '',
      qrIdentifier: json['qr_identifier'] as String? ?? '',
      costPrice: double.tryParse('${json['cost_price'] ?? 0}') ?? 0,
      sellingPrice: double.tryParse('${json['selling_price'] ?? 0}') ?? 0,
      currentStock: double.tryParse('${json['current_stock'] ?? 0}') ?? 0,
      storageLocation: json['storage_location'] as String? ?? '',
    );
  }
}

class Product {
  const Product({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.brandId,
    required this.brandName,
    required this.baseName,
    required this.description,
    required this.imageUrl,
    required this.isActive,
    required this.variants,
  });

  final int id;
  final int categoryId;
  final String categoryName;
  final int brandId;
  final String brandName;
  final String baseName;
  final String description;
  final String imageUrl;
  final bool isActive;
  final List<ProductVariant> variants;

  Product copyWith({
    int? id,
    int? categoryId,
    String? categoryName,
    int? brandId,
    String? brandName,
    String? baseName,
    String? description,
    String? imageUrl,
    bool? isActive,
    List<ProductVariant>? variants,
  }) {
    return Product(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      brandId: brandId ?? this.brandId,
      brandName: brandName ?? this.brandName,
      baseName: baseName ?? this.baseName,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      isActive: isActive ?? this.isActive,
      variants: variants ?? this.variants,
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      categoryId: json['category'] as int,
      categoryName: json['category_name'] as String? ?? '',
      brandId: json['brand'] as int,
      brandName: json['brand_name'] as String? ?? '',
      baseName: json['base_name'] as String,
      description: json['description'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      variants: (json['variants'] as List<dynamic>? ?? const [])
          .map(
            (variant) =>
                ProductVariant.fromJson(variant as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}
