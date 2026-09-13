import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:flutter/material.dart';

class InventoryAdjustStockResult {
  const InventoryAdjustStockResult({
    required this.quantity,
    required this.reason,
    required this.notes,
  });
  final double quantity;
  final String reason;
  final String notes;
}

class InventoryAdjustStockDialog extends StatefulWidget {
  const InventoryAdjustStockDialog({
    super.key,
    required this.product,
    required this.variant,
  });
  final Product product;
  final ProductVariant variant;

  @override
  State<InventoryAdjustStockDialog> createState() =>
      _InventoryAdjustStockDialogState();
}

class _InventoryAdjustStockDialogState
    extends State<InventoryAdjustStockDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _quantity = TextEditingController(
    text: widget.variant.currentStock.toStringAsFixed(0),
  );
  final _notes = TextEditingController();
  String _reason = 'Count Correction';

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quantity =
        double.tryParse(_quantity.text) ?? widget.variant.currentStock;
    final difference = quantity - widget.variant.currentStock;
    return AlertDialog(
      title: const Text('Adjust Stock'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.product.baseName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(widget.variant.variantName),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Current system quantity: ${widget.variant.currentStock.toStringAsFixed(0)}',
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _quantity,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Actual / New Quantity',
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) {
                    final parsed = double.tryParse(value ?? '');
                    if (parsed == null || parsed < 0) {
                      return 'Enter a valid non-negative quantity.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Difference: ${difference > 0 ? '+' : ''}${difference.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: difference < 0 ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  items:
                      const [
                            'Count Correction',
                            'Damaged Items',
                            'Shrinkage / Loss',
                            'Supplier Return',
                          ]
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                  onChanged: (value) =>
                      setState(() => _reason = value ?? _reason),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              InventoryAdjustStockResult(
                quantity: double.parse(_quantity.text),
                reason: _reason,
                notes: _notes.text,
              ),
            );
          },
          child: const Text('Confirm Adjustment'),
        ),
      ],
    );
  }
}
