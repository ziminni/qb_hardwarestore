import 'package:client/core/constants/app_colors.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:flutter/material.dart';

class PosProductBrowser extends StatelessWidget {
  const PosProductBrowser({
    super.key,
    required this.products,
    required this.onSearch,
    required this.onSelect,
  });

  final List<PosCatalogItem> products;
  final ValueChanged<String> onSearch;
  final ValueChanged<PosCatalogItem> onSelect;

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
                    mainAxisExtent: 180,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final lowStock = product.availableSaleQuantity <= 10;
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
                                    product.unit,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '${product.productName}\n',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                      TextSpan(
                                        text: '${product.variantName}\n',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                      TextSpan(
                                        text:
                                            '${product.availableSaleQuantity.toStringAsFixed(2)} ${product.unit} available',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: lowStock
                                                  ? AppColors.warning
                                                  : AppColors.textSecondary,
                                            ),
                                      ),
                                    ],
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '₱${product.unitPrice.toStringAsFixed(2)} / ${product.unit}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
