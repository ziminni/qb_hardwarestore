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
    return AlertDialog(
      title: Text('Discount · ${line.productName}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${formatPeso(line.total)} on this line',
              style: const TextStyle(color: Color(0xFF6E6E6E), fontSize: 12.5),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 10),
            TextFormField(
              key: const ValueKey('pos-line-discount-value'),
              controller: _value,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _kind == DiscountKind.amount
                    ? 'Discount amount'
                    : 'Discount percent',
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
            const SizedBox(height: 10),
            TextFormField(
              key: const ValueKey('pos-line-discount-reason'),
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason for the discount',
              ),
              validator: (value) {
                final amount = double.tryParse(_value.text.trim()) ?? 0;
                if (amount > 0 && (value ?? '').trim().isEmpty) {
                  return 'A discount needs a reason';
                }
                return null;
              },
            ),
          ],
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
