import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/features/products/viewmodels/products_mock_data.dart';
import 'package:client/features/products/widgets/products_summary_card.dart';
import 'package:client/features/products/widgets/products_table.dart';
import 'package:client/features/products/widgets/products_toolbar.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final products = ProductsMockData.products;
    final activeCount = products.where((product) => product.isActive).length;
    final categoryCount = products
        .map((product) => product.categoryId)
        .toSet()
        .length;
    final brandCount = products
        .map((product) => product.brandId)
        .toSet()
        .length;

    return InventorySkeletonLayout(
      title: 'Products',
      subtitle: 'View and organize the hardware product catalog.',
      selectedNavigationIndex: 1,
      onNavigationSelected: (index) {
        if (index == 0) context.go(AppRoutes.inventoryDashboard);
        if (index == 1) context.go(AppRoutes.inventoryProducts);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth < 760
                  ? constraints.maxWidth
                  : 190.0;

              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: ProductsSummaryCard(
                      label: 'Total products',
                      value: '${products.length}',
                      icon: Icons.inventory_2_outlined,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: ProductsSummaryCard(
                      label: 'Active',
                      value: '$activeCount',
                      icon: Icons.check_circle_outline,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: ProductsSummaryCard(
                      label: 'Categories',
                      value: '$categoryCount',
                      icon: Icons.category_outlined,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: ProductsSummaryCard(
                      label: 'Brands',
                      value: '$brandCount',
                      icon: Icons.sell_outlined,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          const ProductsToolbar(),
          const SizedBox(height: AppSpacing.xl),
          ProductsTable(products: products),
        ],
      ),
    );
  }
}
