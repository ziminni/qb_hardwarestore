import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/measure_ruler.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One line of a document sheet, already resolved to something a human reads.
///
/// The three sales documents carry different line types on the wire
/// (`QuotationLineItem`, `OrderLineItem`, `InventorySaleLine`), so each page maps
/// its own into this shape. That mapping is the only place that knows a wire
/// type; the sheet stays a dumb renderer.
class SalesDocumentLine {
  const SalesDocumentLine({
    required this.name,
    required this.qty,
    required this.unitPrice,
  });

  final String name;
  final double qty;
  final double unitPrice;

  double get subtotal => qty * unitPrice;
}

/// A quantity in the app's one quantity format (D7).
///
/// Kept as a named helper because three call sites read better with it, but the
/// rule is [formatQuantity]'s: a whole count keeps no decimals, a fractional one
/// drops trailing zeros, and thousands are grouped. The old local rule printed
/// `1248` where every other screen prints `1,248`.
String salesQty(num amount) => formatQuantity(amount);

/// Resolves a `variant_uom` id to a readable line name.
///
/// The wire carries only the id: `QuotationItemSerializer` and
/// `SalesOrderItemSerializer` expose `variant_uom`, not a name (decision D-02
/// accepted this rather than adding a backend field). The catalogue is already
/// loaded app-wide, so the name comes from there.
///
/// Falls back to `Variant unit #<id>` when the catalogue has no such unit or was
/// never loaded — a manager who opens the sheet first must still see WHAT was
/// ordered. It never throws.
String variantUomName(InventoryViewmodel? inventory, int variantUomId) {
  if (inventory != null) {
    for (final item in inventory.catalogue) {
      if (item.uom.id == variantUomId) {
        return '${item.displayName} (${item.uom.uomName})';
      }
    }
  }
  return 'Variant unit #$variantUomId';
}

/// Opens a read-only document sheet (decision D-02 option A).
Future<void> showSalesDocumentSheet(
  BuildContext context, {
  required String title,
  required List<(String, String)> fields,
  required List<SalesDocumentLine> lines,
  required num total,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SalesDocumentSheet(
      title: title,
      fields: fields,
      lines: lines,
      total: total,
    ),
  );
}

/// A document, read-only.
///
/// Strictly view: no `TextField`, no submit button. D-02 decided View is a
/// display action — create/edit/delete have no scope and no wired backend for
/// the sales role, so there is deliberately nothing here to press.
///
/// Scrollable with `isScrollControlled`, because a long order has more lines
/// than a half-height sheet shows. The header, the label/value rows and the gold
/// total bar come from the shared dialog family, so a sale, a quotation, an
/// order and a return all read the same way whichever role opened them.
class SalesDocumentSheet extends StatelessWidget {
  const SalesDocumentSheet({
    super.key,
    required this.title,
    required this.fields,
    required this.lines,
    required this.total,
  });

  final String title;
  final List<(String, String)> fields;
  final List<SalesDocumentLine> lines;
  final num total;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      // The sheet takes focus when it opens, so Esc reaches the shortcut above.
      child: Focus(
        autofocus: true,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const HexIconBadge(
                      icon: Icons.receipt_long_outlined,
                      size: 40,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.h3.copyWith(height: 1.2),
                          ),
                          Text(
                            'A saved record, read only.',
                            style: AppTextStyles.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const MeasureRuler(height: 6),
                const SizedBox(height: AppSpacing.lg),
                for (final field in fields)
                  DetailRow(label: field.$1, value: field.$2, labelWidth: 160),
                const SizedBox(height: AppSpacing.lg),
                const DialogSectionLabel('Items'),
                if (lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text('No items'),
                  )
                else
                  for (final line in lines) _line(line),
                const SizedBox(height: AppSpacing.xl),
                TotalBar(label: 'Total', amount: total),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(SalesDocumentLine line) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              line.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Text(
              '${salesQty(line.qty)} × ${formatPeso(line.unitPrice)}',
              textAlign: TextAlign.right,
              style: AppTextStyles.bodySmall,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: Text(
              formatPeso(line.subtotal),
              textAlign: TextAlign.right,
              style: AppTextStyles.labelLarge.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
