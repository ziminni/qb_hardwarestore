import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/inventory.dart';
import 'package:flutter/material.dart';

class InventoryMovementFilters extends StatelessWidget {
  const InventoryMovementFilters({
    super.key,
    required this.view,
    required this.searchController,
    required this.type,
    required this.category,
    required this.datePreset,
    required this.categories,
    required this.dateLabel,
    required this.onSearch,
    required this.onTypeChanged,
    required this.onCategoryChanged,
    required this.onDateChanged,
    required this.onSort,
    required this.newestFirst,
  });

  final InventoryMovementView view;
  final TextEditingController searchController;
  final InventoryMovementType? type;
  final String? category;
  final InventoryDatePreset datePreset;
  final List<Category> categories;
  final String dateLabel;
  final ValueChanged<String> onSearch;
  final ValueChanged<InventoryMovementType?> onTypeChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<InventoryDatePreset> onDateChanged;
  final VoidCallback onSort;
  final bool newestFirst;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: TextField(
            controller: searchController,
            onChanged: onSearch,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Product, SKU, or reference',
            ),
          ),
        ),
        if (view != InventoryMovementView.balance)
          SizedBox(
            width: 205,
            child: DropdownButtonFormField<InventoryMovementType?>(
              isExpanded: true,
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Movement type'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All movement types'),
                ),
                ...InventoryMovementType.values.map(
                  (item) =>
                      DropdownMenuItem(value: item, child: Text(item.label)),
                ),
              ],
              onChanged: onTypeChanged,
            ),
          ),
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<String?>(
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('All categories'),
              ),
              ...categories.map(
                (item) =>
                    DropdownMenuItem(value: item.name, child: Text(item.name)),
              ),
            ],
            onChanged: onCategoryChanged,
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<InventoryDatePreset>(
            initialValue: datePreset,
            decoration: const InputDecoration(labelText: 'Date range'),
            items: InventoryDatePreset.values
                .map(
                  (item) =>
                      DropdownMenuItem(value: item, child: Text(item.label)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) onDateChanged(value);
            },
          ),
        ),
        Chip(label: Text(dateLabel)),
        if (view != InventoryMovementView.balance)
          OutlinedButton.icon(
            onPressed: onSort,
            icon: const Icon(Icons.sort),
            label: Text(newestFirst ? 'Newest first' : 'Oldest first'),
          ),
      ],
    );
  }
}
