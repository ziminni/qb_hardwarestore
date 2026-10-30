import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/data/models/product.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/status_pill.dart';
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
    final differenceColor = difference < 0
        ? AppColors.error
        : difference > 0
        ? AppColors.success
        : AppColors.textSecondary;
    return AppDialog(
      icon: Icons.tune_rounded,
      title: 'Adjust Stock',
      subtitle: '${widget.product.baseName} · ${widget.variant.variantName}',
      width: 540,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _QuantityBox(
                    label: 'System quantity',
                    value: widget.variant.currentStock.toStringAsFixed(0),
                    unit: widget.variant.baseUomCode,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.brandGold,
                  ),
                ),
                Expanded(
                  child: _QuantityBox(
                    label: 'New quantity',
                    value: quantity.toStringAsFixed(0),
                    unit: widget.variant.baseUomCode,
                    highlighted: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                label:
                    'Difference: ${difference > 0 ? '+' : ''}${difference.toStringAsFixed(0)}',
                color: differenceColor,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const DialogSectionLabel('Adjustment'),
            TextFormField(
              controller: _quantity,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Actual / New Quantity',
                prefixIcon: Icon(Icons.numbers_rounded),
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
                        (item) =>
                            DropdownMenuItem(value: item, child: Text(item)),
                      )
                      .toList(),
              onChanged: (value) => setState(() => _reason = value ?? _reason),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
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
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Confirm Adjustment'),
        ),
      ],
    );
  }
}

class _QuantityBox extends StatelessWidget {
  const _QuantityBox({
    required this.label,
    required this.value,
    required this.unit,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final String unit;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.brandBlack : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(
          color: highlighted ? AppColors.brandBlack : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              color: highlighted
                  ? AppColors.brandGold
                  : AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: highlighted
                        ? AppColors.brandWhite
                        : AppColors.textPrimary,
                  ),
                ),
                TextSpan(
                  text: '  $unit',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: highlighted
                        ? AppColors.brandGoldLight
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
