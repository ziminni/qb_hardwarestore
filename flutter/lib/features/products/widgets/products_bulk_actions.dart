import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class ProductsBulkActions extends StatelessWidget {
  const ProductsBulkActions({
    super.key,
    required this.selectedCount,
    required this.onActivate,
    required this.onDeactivate,
    required this.onClear,
  });

  final int selectedCount;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        Text('$selectedCount selected'),
        OutlinedButton(onPressed: onActivate, child: const Text('Activate')),
        OutlinedButton(
          onPressed: onDeactivate,
          child: const Text('Deactivate'),
        ),
        TextButton(onPressed: onClear, child: const Text('Clear selection')),
      ],
    );
  }
}
