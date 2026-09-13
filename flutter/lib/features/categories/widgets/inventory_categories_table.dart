import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/category.dart';
import 'package:flutter/material.dart';

class InventoryCategoriesTable extends StatelessWidget {
  const InventoryCategoriesTable({
    super.key,
    required this.categories,
    required this.productCount,
    required this.onView,
    required this.onEdit,
    required this.onArchive,
  });

  final List<Category> categories;
  final int Function(int categoryId) productCount;
  final ValueChanged<Category> onView;
  final ValueChanged<Category> onEdit;
  final ValueChanged<Category> onArchive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(colors.secondaryContainer),
          columns: const [
            DataColumn(label: Text('Category Name')),
            DataColumn(label: Text('Description')),
            DataColumn(label: Text('Products')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: categories
              .map(
                (category) => DataRow(
                  cells: [
                    DataCell(
                      Text(
                        category.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    DataCell(
                      SizedBox(width: 320, child: Text(category.description)),
                    ),
                    DataCell(Text('${productCount(category.id)}')),
                    DataCell(
                      Chip(
                        label: Text(category.isActive ? 'Active' : 'Archived'),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'View category',
                            onPressed: () => onView(category),
                            icon: const Icon(
                              Icons.visibility_outlined,
                              size: 18,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit category',
                            onPressed: () => onEdit(category),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            tooltip: 'Archive category',
                            onPressed: category.isActive
                                ? () => onArchive(category)
                                : null,
                            icon: const Icon(Icons.archive_outlined, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
