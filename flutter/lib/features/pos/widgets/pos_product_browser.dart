import 'package:client/core/constants/app_colors.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:flutter/material.dart';

class PosProductBrowser extends StatelessWidget {
  const PosProductBrowser({
    super.key,
    required this.products,
    required this.onSearch,
    required this.onSelect,
  });

  final List<ProductTrackingConfiguration> products;
  final ValueChanged<String> onSearch;
  final ValueChanged<ProductTrackingConfiguration> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: onSearch,
          decoration: const InputDecoration(
            hintText: 'Search or scan a product',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${products.length} products available',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: products.isEmpty
              ? const Center(child: Text('No products match your search.'))
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisExtent: 156,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final lowStock =
                        product.totalBaseQuantity <= product.reorderLevel;
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onSelect(product),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.inventory_2_outlined),
                                  const Spacer(),
                                  Text(
                                    product.method.label.replaceFirst(
                                      'By ',
                                      '',
                                    ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                product.productName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${product.totalBaseQuantity.toStringAsFixed(2)} ${product.baseUnit} available',
                                style: TextStyle(
                                  color: lowStock
                                      ? AppColors.warning
                                      : AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'From ₱${product.sellingPrice.toStringAsFixed(2)} / ${product.baseUnit}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
