import 'dart:typed_data';

import 'package:client/core/format/format.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/reports/report_pdf.dart';
import 'package:client/shared/widgets/settings_side_layout.dart'
    show StoreInformationPanel;

/// Builds a printable/shareable Purchase Order PDF through the shared store
/// letterhead builder ([renderReportPdf]).
class PurchaseOrderPdf {
  const PurchaseOrderPdf._();

  static String fileName(int poId) => 'PO-$poId.pdf';
}

/// What the Purchase Order prints, before PDF layout. Split out so tests can
/// inspect every line and total without decoding PDF bytes.
ReportPdfContent purchaseOrderPdfContent(PurchaseOrder order) {
  final expected = order.expectedDelivery == null
      ? 'Not set'
      : formatDate(order.expectedDelivery!);
  final filters = <String>[
    'Status: ${order.status.label}',
    'Expected delivery: $expected',
    if (order.createdBy.trim().isNotEmpty)
      'Prepared by: ${order.createdBy.trim()}',
    if (order.notes.trim().isNotEmpty) 'Notes: ${order.notes.trim()}',
  ];

  final rows = <List<String>>[
    for (final item in order.items)
      [
        item.productName.trim().isNotEmpty
            ? '${item.productName.trim()} · ${item.variantName}'
            : item.variantName,
        item.uomCode.isEmpty
            ? formatQuantity(item.quantity)
            : '${formatQuantity(item.quantity)} ${item.uomCode}',
        item.uomCode.isEmpty
            ? formatQuantity(item.receivedQuantity)
            : '${formatQuantity(item.receivedQuantity)} ${item.uomCode}',
        formatPesoForPrint(item.unitCost),
        formatPesoForPrint(item.subtotal),
      ],
    if (order.items.isNotEmpty)
      [
        'Order total',
        '',
        '',
        order.discountAmount > 0
            ? 'Disc -${formatPesoForPrint(order.discountAmount)}'
            : '',
        formatPesoForPrint(order.displayTotal),
      ],
  ];

  return ReportPdfContent(
    title: 'Purchase Order PO-${order.id}',
    period: 'Ordered on ${formatDate(order.orderDate)}',
    filters: filters,
    storeName: StoreInformationPanel.storeName,
    kpis: [
      (
        label: 'Supplier',
        value: order.supplierName.isEmpty
            ? 'Supplier #${order.supplierId}'
            : order.supplierName,
        caption: null,
      ),
      (label: 'Status', value: order.status.label, caption: null),
      (
        label: 'Order Total',
        value: formatPesoForPrint(order.displayTotal),
        caption: order.hasServerTotals && order.vatAmount != null
            ? 'VAT ${formatPesoForPrint(order.vatAmount!)}'
            : null,
      ),
    ],
    columns: const ['Item', 'Ordered', 'Received', 'Unit Cost', 'Line Total'],
    rows: rows,
    emptyMessage: 'No line items on this purchase order.',
  );
}

/// Renders the Purchase Order as PDF bytes, ready for `Printing.sharePdf`.
Future<Uint8List> renderPurchaseOrderPdf(
  PurchaseOrder order, {
  String generatedBy = '',
}) {
  final content = purchaseOrderPdfContent(order);
  return renderReportPdf(
    title: content.title,
    period: content.period,
    filters: content.filters,
    generatedBy: generatedBy.isNotEmpty ? generatedBy : order.createdBy,
    storeName: content.storeName,
    kpis: content.kpis,
    columns: content.columns,
    rows: content.rows,
    emptyMessage: content.emptyMessage,
  );
}
