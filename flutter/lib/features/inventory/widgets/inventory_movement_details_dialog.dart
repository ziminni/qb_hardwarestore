import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/widgets/inventory_movement_badge.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

class InventoryMovementDetailsDialog extends StatelessWidget {
  const InventoryMovementDetailsDialog({
    super.key,
    required this.movement,
    required this.product,
    required this.variant,
  });

  final InventoryMovement movement;
  final Product product;
  final ProductVariant variant;

  String _quantity(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final unit = movement.unit ?? variant.baseUomCode;
    final detail = movement.physicalDetail;
    final changeColor = movement.isIncoming
        ? AppColors.success
        : AppColors.error;
    return AppDialog(
      icon: movement.isIncoming ? Icons.south_west : Icons.north_east,
      title: 'Movement details',
      subtitle: 'Movement #${movement.id} · ${movement.reference}',
      width: 640,
      headerTrailing: InventoryMovementBadge(type: movement.type),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadii.medium),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _flowValue(
                  'Previous',
                  '${_quantity(movement.previousStock)} $unit',
                ),
                const Icon(Icons.chevron_right, color: AppColors.brandGold),
                _flowValue(
                  movement.isIncoming ? 'Stock in' : 'Stock out',
                  '${movement.isIncoming ? '+' : ''}${_quantity(movement.quantityChange)} $unit',
                  color: changeColor,
                ),
                const Icon(Icons.chevron_right, color: AppColors.brandGold),
                _flowValue(
                  'New stock',
                  '${_quantity(movement.newStock)} $unit',
                  emphasized: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const DialogSectionLabel('Record'),
          DetailRow(
            label: 'Date & time',
            value:
                '${movement.timestamp.year}-${movement.timestamp.month.toString().padLeft(2, '0')}-${movement.timestamp.day.toString().padLeft(2, '0')} ${movement.timestamp.hour.toString().padLeft(2, '0')}:${movement.timestamp.minute.toString().padLeft(2, '0')}',
          ),
          DetailRow(
            label: 'Product',
            value: '${product.baseName} — ${variant.variantName}',
          ),
          DetailRow(label: 'SKU', value: variant.sku),
          DetailRow(
            label: 'Direction',
            value: movement.isIncoming ? 'STOCK IN' : 'STOCK OUT',
            valueColor: changeColor,
          ),
          DetailRow(
            label: 'Source',
            value: movement.source ?? movement.type.label,
          ),
          DetailRow(label: 'Reference', value: movement.reference),
          DetailRow(label: 'Reason', value: movement.reason),
          if (movement.notes.isNotEmpty)
            DetailRow(label: 'Notes', value: movement.notes),
          DetailRow(label: 'Performed by', value: movement.userName),
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.xl),
            const DialogSectionLabel('Physical inventory effect'),
            if (detail.packageDescription != null)
              DetailRow(label: 'Package', value: detail.packageDescription!),
            if (detail.packageEffect != null)
              DetailRow(label: 'Package effect', value: detail.packageEffect!),
            if (detail.sourcePiece != null)
              DetailRow(
                label: 'Source piece',
                value: '${_quantity(detail.sourcePiece!)} m',
              ),
            if (detail.remainingPiece != null)
              DetailRow(
                label: 'Remaining piece',
                value: '${_quantity(detail.remainingPiece!)} m',
              ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _flowValue(
    String label,
    String value, {
    Color? color,
    bool emphasized = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(letterSpacing: 1.1),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyLarge.copyWith(
              fontSize: emphasized ? 20 : 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
