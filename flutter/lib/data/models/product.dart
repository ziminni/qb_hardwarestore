class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.variantName,
    required this.baseUomCode,
    required this.isActive,
  });

  final int id;
  final String variantName;
  final String baseUomCode;
  final bool isActive;

  factory ProductVariant.fromJson(Map<String, dynamic> json) {
    return ProductVariant(
      id: json['id'] as int,
      variantName: json['variant_name'] as String,
      baseUomCode: json['base_uom_code'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
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
