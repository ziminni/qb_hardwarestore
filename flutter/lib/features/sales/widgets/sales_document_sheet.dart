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
    this.fulfilledQty,
    this.remainingQty,
    this.availableQty,
  });

  final String name;

  /// What was ordered.
  final double qty;
  final double unitPrice;

  /// Order lines only (Phase 7 F1): what has been rung into a sale. Null on a
  /// document with no lifecycle, which is how the sheet knows to stay quiet.
  final double? fulfilledQty;

  /// What is still owed. Derived from [qty] and [fulfilledQty] when the wire
  /// left it out.
  final double? remainingQty;

  /// Sellable stock in this line's unit, when the server sends it (B5). A live
  /// hint only — an order reserves nothing.
  final double? availableQty;

  double get subtotal => qty * unitPrice;

  /// What is still owed on this line.
  double get remaining => remainingQty ?? qty - (fulfilledQty ?? 0);
}

/// What a reader picked on the document sheet. The sheet pops with this rather
/// than acting itself: it is a view, and the page owns the dialogs.
enum SalesDocumentAction { edit, cancel }

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

/// Opens a document sheet (decision D-02 option A).
///
/// [canEdit]/[canCancel] are decided by the PAGE, from the role and the order's
/// status: the sheet never reads auth, and a sheet with neither flag is the
/// strictly read-only family it was before Phase 7.
Future<SalesDocumentAction?> showSalesDocumentSheet(
  BuildContext context, {
  required String title,
  required List<(String, String)> fields,
  required List<SalesDocumentLine> lines,
  required num total,
  bool canEdit = false,
  bool canCancel = false,
}) {
  return showModalBottomSheet<SalesDocumentAction>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SalesDocumentSheet(
      title: title,
      fields: fields,
      lines: lines,
      total: total,
      canEdit: canEdit,
      canCancel: canCancel,
    ),
  );
}

/// A document, read-only unless the page grants an action.
///
/// Strictly view: no `TextField`, no money on the way in. D-02 decided View is a
/// display action, and that still holds for every posted document; Phase 7 F1
/// added the two LIFECYCLE actions an unfulfilled order has (Edit, Cancel) for
/// managers, and those close the sheet and hand the choice back to the page.
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
    this.canEdit = false,
    this.canCancel = false,
  });

  final String title;
  final List<(String, String)> fields;
  final List<SalesDocumentLine> lines;
  final num total;
  final bool canEdit;
  final bool canCancel;

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
                if (canEdit || canCancel) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (canCancel)
                        TextButton(
                          key: const ValueKey('so-sheet-cancel'),
                          onPressed: () => Navigator.pop(
                            context,
                            SalesDocumentAction.cancel,
                          ),
                          child: const Text('Cancel'),
                        ),
                      if (canEdit)
                        Padding(
                          padding: const EdgeInsets.only(left: AppSpacing.sm),
                          child: FilledButton.tonal(
                            key: const ValueKey('so-sheet-edit'),
                            onPressed: () => Navigator.pop(
                              context,
                              SalesDocumentAction.edit,
                            ),
                            child: const Text('Edit'),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _line(SalesDocumentLine line) {
    final fulfilled = line.fulfilledQty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
          // Phase 7 F1: an order's progress, and whether today's stock covers
          // what is left. Nothing is reserved, so this is a hint and says so.
          if (fulfilled != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  'Ordered ${salesQty(line.qty)}',
                  'Fulfilled ${salesQty(fulfilled)}',
                  'Remaining ${salesQty(line.remaining)}',
                  ?_stockHint(line),
                ].join(' · '),
                style: AppTextStyles.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  /// "Enough in stock", "Short by N", or nothing when the wire sent no
  /// `available_qty` (a server that predates B5 says nothing rather than "short").
  static String? _stockHint(SalesDocumentLine line) {
    final available = line.availableQty;
    if (available == null) return null;
    final shortfall = line.remaining - available;
    if (shortfall <= 0) return 'Enough in stock';
    return 'Short by ${salesQty(shortfall)}';
  }
}
