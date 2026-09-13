import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class ProductsToolbar extends StatelessWidget {
  const ProductsToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final search = TextField(
          decoration: const InputDecoration(
            hintText: 'Search products',
            prefixIcon: Icon(Icons.search),
          ),
        );
        final category = DropdownButtonFormField<String>(
          initialValue: 'All categories',
          decoration: const InputDecoration(labelText: 'Category'),
          items:
              const [
                    'All categories',
                    'Cement',
                    'Plumbing',
                    'Lumber',
                    'Electrical',
                  ]
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
          onChanged: (_) {},
        );
        final status = DropdownButtonFormField<String>(
          initialValue: 'All statuses',
          decoration: const InputDecoration(labelText: 'Status'),
          items: const ['All statuses', 'Active', 'Inactive']
              .map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (_) {},
        );
        final addButton = FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('Add product'),
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: AppSpacing.md),
              category,
              const SizedBox(height: AppSpacing.md),
              status,
              const SizedBox(height: AppSpacing.md),
              Align(alignment: Alignment.centerRight, child: addButton),
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 3, child: search),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: category),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: status),
            const SizedBox(width: AppSpacing.lg),
            addButton,
          ],
        );
      },
    );
  }
}
