import 'package:client/core/constants/app_spacing.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:flutter/material.dart';

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

String salesMoney(double amount) => '₱${amount.toStringAsFixed(2)}';

/// Quantities render without a trailing ".0" — a count reading "10.0" looks
/// estimated, and these come from exact batch arithmetic.
String salesQty(num amount) =>
    amount % 1 == 0 ? '${amount.toInt()}' : '$amount';

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
  required String total,
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
/// than a half-height sheet shows.
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
  final String total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final field in fields)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 160,
                      child: Text(
                        field.$1,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(child: Text(field.$2)),
                  ],
                ),
              ),
            const Divider(height: AppSpacing.xl),
            Text(
              'Items',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (lines.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Text('No items'),
              )
            else
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(child: Text(line.name)),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${salesQty(line.qty)} × ${salesMoney(line.unitPrice)}',
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          salesMoney(line.subtotal),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
            const Divider(height: AppSpacing.xl),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Total',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  total,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
