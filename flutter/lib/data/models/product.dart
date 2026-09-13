class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.variantName,
    required this.baseUomCode,
    required this.isActive,
    this.sku = '',
    this.qrIdentifier = '',
    this.costPrice = 0,
    this.sellingPrice = 0,
    this.currentStock = 0,
    this.reorderLevel = 0,
    this.storageLocation = '',
  });

  final int id;
  final String variantName;
  final String baseUomCode;
  final bool isActive;
  final String sku;
  final String qrIdentifier;
  final double costPrice;
  final double sellingPrice;
  final double currentStock;
  final double reorderLevel;
  final String storageLocation;

  ProductVariant copyWith({
    bool? isActive,
    double? currentStock,
    double? reorderLevel,
    String? storageLocation,
  }) {
    return ProductVariant(
      id: id,
      variantName: variantName,
      baseUomCode: baseUomCode,
      isActive: isActive ?? this.isActive,
      sku: sku,
      qrIdentifier: qrIdentifier,
      costPrice: costPrice,
      sellingPrice: sellingPrice,
      currentStock: currentStock ?? this.currentStock,
      reorderLevel: reorderLevel ?? this.reorderLevel,
      storageLocation: storageLocation ?? this.storageLocation,
    );
  }

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'] as int,
      variantName: json['variant_name'] as String,
      baseUomCode: json['base_uom_code'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
      sku: json['sku'] as String? ?? '',
      qrIdentifier: json['qr_identifier'] as String? ?? '',
      costPrice: double.tryParse('${json['cost_price'] ?? 0}') ?? 0,
      sellingPrice: double.tryParse('${json['selling_price'] ?? 0}') ?? 0,
      currentStock: double.tryParse('${json['current_stock'] ?? 0}') ?? 0,
      reorderLevel: double.tryParse('${json['reorder_level'] ?? 0}') ?? 0,
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
