import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/widgets/inventory_movement_badge.dart';
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
    return AlertDialog(
      title: const Text('Movement details'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InventoryMovementBadge(type: movement.type),
                  const SizedBox(width: AppSpacing.sm),
                  Chip(
                    label: Text(movement.isIncoming ? 'STOCK IN' : 'STOCK OUT'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              _row('Movement ID', '#${movement.id}'),
              _row(
                'Date & time',
                '${movement.timestamp.year}-${movement.timestamp.month.toString().padLeft(2, '0')}-${movement.timestamp.day.toString().padLeft(2, '0')} ${movement.timestamp.hour.toString().padLeft(2, '0')}:${movement.timestamp.minute.toString().padLeft(2, '0')}',
              ),
              _row('Product', '${product.baseName} — ${variant.variantName}'),
              _row('SKU', variant.sku),
              _row(
                'Quantity',
                '${movement.isIncoming ? '+' : ''}${_quantity(movement.quantityChange)} $unit',
              ),
              _row(
                'Previous stock',
                '${_quantity(movement.previousStock)} $unit',
              ),
              _row('New stock', '${_quantity(movement.newStock)} $unit'),
              _row('Source', movement.source ?? movement.type.label),
              _row('Reference', movement.reference),
              _row('Reason', movement.reason),
              if (movement.notes.isNotEmpty) _row('Notes', movement.notes),
              _row('Performed by', movement.userName),
              if (detail != null) ...[
                const Divider(height: AppSpacing.xxl),
                Text(
                  'Physical inventory effect',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (detail.packageDescription != null)
                  _row('Package', detail.packageDescription!),
                if (detail.packageEffect != null)
                  _row('Package effect', detail.packageEffect!),
                if (detail.sourcePiece != null)
                  _row('Source piece', '${_quantity(detail.sourcePiece!)} m'),
                if (detail.remainingPiece != null)
                  _row(
                    'Remaining piece',
                    '${_quantity(detail.remainingPiece!)} m',
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 150, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
