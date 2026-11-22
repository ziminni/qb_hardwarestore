import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/sale_discount.dart';
import 'package:flutter/material.dart';

/// What the line-discount dialog handed back.
///
/// Null means the cashier backed out; a result with a null [discount] means "take
/// the discount off this line". A plain `PosDiscount?` could not tell those apart,
/// and cancelling must not silently clear a discount the cashier already gave.
class PosLineDiscountResult {
  const PosLineDiscountResult(this.discount);

  final PosDiscount? discount;
}

/// The discount given on ONE cart line (beside the sale's own, whole-sale discount).
///
/// The server refuses a reasonless discount and refuses one larger than the line, so
/// the fields enforce the same two rules here — with the same sentences the server's
/// codes map to.
class PosLineDiscountDialog extends StatefulWidget {
  const PosLineDiscountDialog({super.key, required this.line});

  final PosCartLine line;

  @override
  State<PosLineDiscountDialog> createState() => _PosLineDiscountDialogState();
}

class _PosLineDiscountDialogState extends State<PosLineDiscountDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _value = TextEditingController(
    text: switch (widget.line.discount) {
      null => '',
      final discount => formatQuantity(discount.value),
    },
  );
  late final _reason = TextEditingController(
    text: widget.line.discount?.reason ?? '',
  );
  late DiscountKind _kind = widget.line.discount?.kind ?? DiscountKind.amount;

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final value = double.tryParse(_value.text.trim()) ?? 0;
    if (value <= 0) {
      Navigator.pop(context, const PosLineDiscountResult(null));
      return;
    }
    Navigator.pop(
      context,
      PosLineDiscountResult(
        PosDiscount(kind: _kind, value: value, reason: _reason.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final typed = double.tryParse(_value.text.trim()) ?? 0;
    final previewDiscount = typed <= 0
        ? 0.0
        : _kind == DiscountKind.percent
        ? (line.total * (typed.clamp(0, 100) / 100))
        : typed.clamp(0, line.total).toDouble();
    final previewNet = (line.total - previewDiscount).clamp(0.0, line.total);

    return AlertDialog(
      title: Text('Item Discount · ${line.productName}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Line total',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            formatPeso(line.total),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Discount',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            '-${formatPeso(previewDiscount)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.successText,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'New total',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          Text(
                            formatPeso(previewNet),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final kind in DiscountKind.values) ...[
                    ChoiceChip(
                      label: Text(
                        kind == DiscountKind.amount ? '₱ Amount' : '% Percent',
                      ),
                      selected: _kind == kind,
                      onSelected: (_) => setState(() => _kind = kind),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('pos-line-discount-value'),
                controller: _value,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _kind == DiscountKind.amount
                      ? 'Discount amount'
                      : 'Discount percent',
                  prefixText: _kind == DiscountKind.amount ? '₱ ' : null,
                  suffixText: _kind == DiscountKind.percent ? '%' : null,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  final parsed = double.tryParse((value ?? '').trim());
                  if (parsed == null || parsed == 0) return null;
                  if (parsed < 0) return 'A discount cannot be negative';
                  if (_kind == DiscountKind.percent && parsed > 100) {
                    return 'A discount cannot be more than 100 percent';
                  }
                  if (_kind == DiscountKind.amount && parsed > line.total) {
                    return 'A discount cannot be more than this line';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('pos-line-discount-reason'),
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Reason for the discount',
                  hintText: 'e.g. Bulk buyer, minor packaging dent',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final amount = double.tryParse(_value.text.trim()) ?? 0;
                  if (amount > 0 && (value ?? '').trim().isEmpty) {
                    return 'A discount needs a reason';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              const Text(
                'Note: Per-item discounts cannot be combined with a whole-sale discount on the same sale.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (line.discount != null)
          TextButton(
            key: const ValueKey('pos-line-discount-remove'),
            onPressed: () =>
                Navigator.pop(context, const PosLineDiscountResult(null)),
            child: const Text('Remove discount'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('pos-line-discount-save'),
          onPressed: _save,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
