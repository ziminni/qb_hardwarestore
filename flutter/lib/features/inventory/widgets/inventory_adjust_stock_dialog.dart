import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/stock_on_hand.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

class InventoryAdjustStockResult {
  const InventoryAdjustStockResult({
    required this.quantity,
    required this.reason,
    required this.notes,
    this.locationId,
  });
  final double quantity;
  final String reason;
  final String notes;

  /// The shelf this count belongs to (Phase 9 F2, decision 21 §8). Null means
  /// the product's home shelf, which is the server's own default.
  final int? locationId;
}

/// Count stock: the system's figure, the counted one, and the difference.
///
/// Phase 1d Task 10a, decision 17: it wears the shared dialog family, so the two
/// figures sit in boxes side by side ("System quantity -> New quantity") and the
/// difference is a badge that SAYS it in words. A color alone would tell a
/// colour blind stock manager nothing, and it would print as loose text.
class InventoryAdjustStockDialog extends StatefulWidget {
  const InventoryAdjustStockDialog({
    super.key,
    required this.product,
    required this.variant,
    required this.currentStock,
    this.locations = const [],
    this.stockByLocation = const [],
  });
  final Product product;
  final ProductVariant variant;

  /// Stock on hand, passed in from the batch-backed viewmodel rather than read
  /// off the variant: the variant no longer carries a quantity (decision 02).
  /// Used as the whole-shop figure when no per-shelf rows are given.
  final double currentStock;

  /// The shop's shelves, as the server named them. Empty means this build cannot
  /// offer a choice, and the dialog behaves as it did before Phase 9.
  final List<StorageLocation> locations;

  /// How much of this variant sits on each shelf (the server's on-hand rows).
  final List<StockOnHand> stockByLocation;

  @override
  State<InventoryAdjustStockDialog> createState() =>
      _InventoryAdjustStockDialogState();
}

class _InventoryAdjustStockDialogState
    extends State<InventoryAdjustStockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _notes = TextEditingController();
  String _reason = InventoryViewmodel.adjustmentReasons.first;

  /// The shelf this count belongs to. Starts on the product's HOME shelf (the
  /// server's `is_home` row), which is also what an omitted `location` means.
  int? _locationId;

  @override
  void initState() {
    super.initState();
    // Home first: an adjustment made without thinking about shelves must land
    // where every adjustment landed before Phase 9.
    for (final row in widget.stockByLocation) {
      if (row.isHome) {
        _locationId = row.locationId;
        break;
      }
    }
    // The field starts at THAT shelf's count — the figure the counter edits —
    // and at the whole-shop figure when no per-shelf rows were handed in.
    _quantity.text = _plainQuantity(_systemQuantity);
  }

  /// The chosen shelf, when the server listed it.
  StorageLocation? get _location {
    for (final location in widget.locations) {
      if (location.id == _locationId) return location;
    }
    return null;
  }

  /// How much sits on the chosen shelf. Falls back to the whole-shop figure when
  /// this build has no per-shelf rows (no adjacent shell hole: the dialog still
  /// adjusts the shop, as it did before Phase 9).
  double get _systemQuantity {
    if (widget.stockByLocation.isEmpty) return widget.currentStock;
    for (final row in widget.stockByLocation) {
      if (row.locationId == _locationId) return row.qty;
    }
    return 0;
  }

  /// Picking another shelf re-reads the count THERE: the field is that shelf's
  /// figure, and carrying the old shelf's number over would suggest stock that
  /// shelf never had.
  void _selectLocation(int? locationId) {
    setState(() {
      _locationId = locationId;
      _quantity.text = _plainQuantity(_systemQuantity);
    });
  }

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quantity = double.tryParse(_quantity.text) ?? _systemQuantity;
    final difference = quantity - _systemQuantity;
    final unit = widget.variant.baseUomCode;
    // An inactive shelf may only LOSE stock (decision 21 §8/§11): the server
    // refuses an addition there, so the dialog says why instead of letting the
    // press become a 400.
    final inactive = _location?.isActive == false;

    return AppDialog(
      icon: Icons.tune_rounded,
      title: 'Adjust Stock',
      subtitle: '${widget.product.baseName} · ${widget.variant.variantName}',
      width: 560,
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
                    value: formatQuantity(_systemQuantity),
                    unit: unit,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: AppColors.brandGold,
                  ),
                ),
                Expanded(
                  child: _QuantityBox(
                    label: 'New quantity',
                    value: formatQuantity(quantity),
                    unit: unit,
                    highlighted: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: _DifferenceBadge(difference: difference),
            ),
            const SizedBox(height: AppSpacing.xl),
            const DialogSectionLabel('Adjustment'),
            // Phase 9 F2 (decision 21 §8): WHICH shelf this count is about. Only
            // offered when the shop has more than one shelf to choose between.
            if (widget.locations.length > 1) ...[
              DropdownButtonFormField<int>(
                key: const Key('adjust-location'),
                isExpanded: true,
                initialValue: _location?.id,
                decoration: const InputDecoration(labelText: 'Location'),
                items: [
                  for (final location in widget.locations)
                    DropdownMenuItem(
                      value: location.id,
                      child: Text(
                        location.isActive
                            ? location.name
                            : '${location.name} (inactive)',
                      ),
                    ),
                ],
                onChanged: _selectLocation,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
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
                if (inactive && parsed > _systemQuantity) {
                  return '${_location!.name} is deactivated: stock can only be '
                      'removed there.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              // The list lives on the viewmodel, which also owns the wording ->
              // `adjustment_type` mapping, so the two cannot drift. "Supplier
              // Return" is not offered (Phase 8 F2): a return to a supplier goes
              // through its own flow, and the server refuses a RETURN adjustment.
              items: InventoryViewmodel.adjustmentReasons
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
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
                // Only a shelf with a real id travels: a dialog opened without
                // the location list sends none, and the server uses home.
                locationId: _location?.id,
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

/// The count the field starts at, without thousands groups: `formatQuantity`
/// prints `1,200`, which `double.tryParse` refuses, and rounding it to a whole
/// number would turn a measured 7.5 kg into 8. This is an editable number, not
/// a displayed quantity, so it is the one place decimals stay unformatted.
String _plainQuantity(double value) =>
    value == value.roundToDouble() ? '${value.round()}' : '$value';

/// One figure in the System -> New pair. The new count is highlighted because
/// it is the one the clerk typed.
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
              fontWeight: FontWeight.w700,
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

/// The difference as words in a badge: "Increase by 50". The tone is the hint,
/// the sentence is the message. The unit is already on both boxes above, so the
/// badge stays short enough for a narrow window.
class _DifferenceBadge extends StatelessWidget {
  const _DifferenceBadge({required this.difference});

  final double difference;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = difference == 0
        ? ('No change', StatusTone.neutral)
        : difference > 0
        ? ('Increase by ${formatQuantity(difference)}', StatusTone.success)
        : (
            'Decrease by ${formatQuantity(difference.abs())}',
            StatusTone.warning,
          );
    return StatusBadge(label: label, tone: tone);
  }
}
