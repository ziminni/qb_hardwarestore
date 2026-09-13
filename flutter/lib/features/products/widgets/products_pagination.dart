import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class ProductsPagination extends StatelessWidget {
  const ProductsPagination({
    super.key,
    required this.firstItem,
    required this.lastItem,
    required this.totalItems,
    required this.currentPage,
    required this.totalPages,
    required this.rowsPerPage,
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
  });

  final int firstItem;
  final int lastItem;
  final int totalItems;
  final int currentPage;
  final int totalPages;
  final int rowsPerPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRowsPerPageChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.sm,
        children: [
          Text(
            totalItems == 0
                ? '0 products'
                : 'Showing $firstItem–$lastItem of $totalItems products',
            style: theme.textTheme.bodySmall,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Rows:'),
              const SizedBox(width: AppSpacing.sm),
              DropdownButton<int>(
                value: rowsPerPage,
                items: const [5, 10, 20]
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text('$value')),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onRowsPerPageChanged(value);
                },
              ),
              const SizedBox(width: AppSpacing.lg),
              IconButton(
                tooltip: 'Previous page',
                onPressed: currentPage > 1
                    ? () => onPageChanged(currentPage - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$currentPage of $totalPages'),
              IconButton(
                tooltip: 'Next page',
                onPressed: currentPage < totalPages
                    ? () => onPageChanged(currentPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
