import 'package:client/data/models/product.dart';

class ProductsMockData {
  ProductsMockData._();

  static const products = [
    Product(
      id: 1,
      categoryId: 1,
      categoryName: 'Cement',
      brandId: 1,
      brandName: 'Holcim',
      baseName: 'Portland Cement',
      description: 'General-purpose Portland cement.',
      imageUrl: '',
      isActive: true,
      variants: [
        ProductVariant(
          id: 1,
          variantName: '40 kg bag',
          baseUomCode: 'BAG',
          isActive: true,
        ),
      ],
    ),
    Product(
      id: 2,
      categoryId: 2,
      categoryName: 'Plumbing',
      brandId: 2,
      brandName: 'Neltex',
      baseName: 'PVC Pipe',
      description: 'PVC pipe for water-line installations.',
      imageUrl: '',
      isActive: true,
      variants: [
        ProductVariant(
          id: 2,
          variantName: '1/2 inch × 3 m',
          baseUomCode: 'PC',
          isActive: true,
        ),
        ProductVariant(
          id: 3,
          variantName: '3/4 inch × 3 m',
          baseUomCode: 'PC',
          isActive: true,
        ),
      ],
    ),
    Product(
      id: 3,
      categoryId: 3,
      categoryName: 'Lumber',
      brandId: 3,
      brandName: 'Queen Builders',
      baseName: 'Marine Plywood',
      description: 'Moisture-resistant plywood sheet.',
      imageUrl: '',
      isActive: true,
      variants: [
        ProductVariant(
          id: 4,
          variantName: '1/4 inch × 4 ft × 8 ft',
          baseUomCode: 'SHEET',
          isActive: true,
        ),
        ProductVariant(
          id: 5,
          variantName: '1/2 inch × 4 ft × 8 ft',
          baseUomCode: 'SHEET',
          isActive: true,
        ),
      ],
    ),
    Product(
      id: 4,
      categoryId: 4,
      categoryName: 'Electrical',
      brandId: 4,
      brandName: 'Royu',
      baseName: 'Convenience Outlet',
      description: 'Duplex convenience outlet.',
      imageUrl: '',
      isActive: false,
      variants: [
        ProductVariant(
          id: 6,
          variantName: 'Universal duplex',
          baseUomCode: 'PC',
          isActive: false,
        ),
      ],
    ),
  ];
}
