import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/returns.dart';
import 'package:flutter/material.dart';

/// One selling unit on the original sale, with the till's stepper.
///
/// The stepper is capped at `remaining_qty` on BOTH ends: the plus button is
/// disabled at the cap, so the screen cannot offer an amount `process_return`
/// would refuse with `RETURN_QTY_EXCEEDED`. A line with nothing left is shown
/// DISABLED rather than hidden, because the cashier must see that the sale had
/// that line and it has already come back.
class PosReturnsLineRow extends StatefulWidget {
  const PosReturnsLineRow({
    super.key,
    required this.line,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    this.onQuantityChanged,
  });

  final ReturnableLine line;

  /// What the cashier stepped up so far (0 until they touch it).
  final double quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  /// Optional direct quantity setter for bulk returns (type a number or tap All).
  final ValueChanged<double>? onQuantityChanged;

  @override
  State<PosReturnsLineRow> createState() => _PosReturnsLineRowState();
}

class _PosReturnsLineRowState extends State<PosReturnsLineRow> {
  late final TextEditingController _controller = TextEditingController(
    text: formatQuantity(widget.quantity),
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant PosReturnsLineRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantity != widget.quantity && !_focusNode.hasFocus) {
      final formatted = formatQuantity(widget.quantity);
      if (_controller.text != formatted) {
        _controller.text = formatted;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commitTyped(String raw) {
    final setter = widget.onQuantityChanged;
    if (setter == null) return;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      setter(0);
      return;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return;
    setter(parsed.clamp(0.0, widget.line.remainingQty));
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final quantity = widget.quantity;
    final enabled = line.hasRemaining;
    final setter = widget.onQuantityChanged;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line.name} (${line.uom})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: enabled ? null : AppColors.textSecondary,
                  ),
                ),
                Text(
                  enabled
                      ? '${formatQuantity(line.remainingQty)} of '
                            '${formatQuantity(line.soldQty)} left · '
                            '${formatQuantity(line.returnedQty)} already '
                            'returned · ${formatPeso(line.unitPrice)}'
                      : 'All ${formatQuantity(line.soldQty)} already returned',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: enabled && quantity > 0 ? widget.onDecrement : null,
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'One fewer',
          ),
          if (setter != null && enabled)
            SizedBox(
              width: 64,
              child: TextField(
                key: ValueKey('return-qty-input-${line.variantUomId}'),
                controller: _controller,
                focusNode: _focusNode,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(),
                ),
                onChanged: _commitTyped,
                onTap: () {
                  _controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _controller.text.length,
                  );
                },
              ),
            )
          else
            SizedBox(
              width: 44,
              child: Text(
                formatQuantity(quantity),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          IconButton(
            onPressed: enabled && quantity < line.remainingQty
                ? widget.onIncrement
                : null,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'One more',
          ),
          if (setter != null && enabled && line.remainingQty > 1)
            TextButton(
              key: ValueKey('return-qty-all-${line.variantUomId}'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(44, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: quantity >= line.remainingQty
                  ? () => setter(0)
                  : () => setter(line.remainingQty),
              child: Text(quantity >= line.remainingQty ? 'Clear' : 'All'),
            ),
        ],
      ),
    );
  }
}
