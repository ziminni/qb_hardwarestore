import 'package:client/core/format/format.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales_module.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_document_list_content.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Store Manager's quotations screen: a shell only (card M3). The list, the
/// search, the status chips and the empty and error states live in
/// [SalesDocumentListContent], which the sales orders screen shows too.
///
/// "New quotation" is GONE (Phase 3 Task 0): the sales-manager decision makes
/// this screen read-only and no create screen or endpoint exists, so the button
/// could only ever do nothing.
class SalesQuotationsPage extends StatefulWidget {
  const SalesQuotationsPage({super.key, this.now});

  /// The clock the "Expired" rule reads. Injected so a test can pin the date a
  /// quotation is judged by instead of following the wall clock. Nullable
  /// because a default value has to be const, so it falls back to `clock.now`.
  final DateTime Function()? now;

  @override
  State<SalesQuotationsPage> createState() => _SalesQuotationsPageState();
}

class _SalesQuotationsPageState extends State<SalesQuotationsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SalesModuleViewmodel>().load();
    });
  }

  /// Opens the read-only document sheet (decision D-02).
  ///
  /// Reads the app-scoped catalogue once per tap to turn `variant_uom` ids into
  /// names. A missing catalogue is not an error: [variantUomName] falls back to
  /// the id.
  void _showQuotationSheet(
    BuildContext context,
    SalesQuotation item,
    DateTime now,
  ) {
    final inventory = context.read<InventoryViewmodel?>();
    showSalesDocumentSheet(
      context,
      title: item.number,
      fields: [
        ('Customer', item.customer),
        ('Status', _statusLabel(item, now)),
        ('Created', formatDate(item.date)),
        ('Valid until', formatDate(item.validUntil)),
        if ((item.notes ?? '').isNotEmpty) ('Notes', item.notes!),
      ],
      lines: [
        for (final line in item.items)
          SalesDocumentLine(
            name: variantUomName(inventory, line.variantUomId),
            qty: line.qty,
            unitPrice: line.unitPrice,
          ),
      ],
      total: formatPeso(item.total),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<SalesModuleViewmodel>();
    final quotations = viewmodel.quotations;
    // Read once per build: an expiry computed from a moving clock could change
    // halfway down the list at midnight.
    final now = widget.now?.call() ?? appClock.now();

    return SalesSkeletonLayout(
      title: 'Quotations',
      subtitle: 'Prepare and track customer estimates before an order.',
      selectedNavigationIndex: 2,
      // The list owns the scrolling, so it builds only the rows on screen.
      scrollable: false,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: SalesDocumentListContent(
        kind: SalesDocumentKind.quotation,
        rows: [for (final item in quotations) _row(item, now)],
        isLoading: viewmodel.isLoading,
        loadError: viewmodel.loadError,
        onRetry: viewmodel.load,
      ),
    );
  }

  SalesDocumentRow _row(SalesQuotation item, DateTime now) {
    return SalesDocumentRow(
      number: item.number,
      customer: item.customer,
      date: item.date,
      validUntil: item.validUntil,
      total: item.total,
      statusLabel: _statusLabel(item, now),
      tone: _statusTone(item, now),
      onOpen: () => _showQuotationSheet(context, item, now),
    );
  }
}

/// Whether [item] has run past its "Valid until" date with nobody closing it.
///
/// Only an OPEN quotation expires: an accepted one is already decided, and one
/// the server marked EXPIRED says so without help. The comparison is by day, so
/// a quotation is valid THROUGH its last day rather than until its midnight.
bool _hasExpired(SalesQuotation item, DateTime now) {
  final open =
      item.status == SalesQuoteStatus.draft ||
      item.status == SalesQuoteStatus.sent;
  if (!open) return false;
  final today = DateTime(now.year, now.month, now.day);
  final limit = DateTime(
    item.validUntil.year,
    item.validUntil.month,
    item.validUntil.day,
  );
  return limit.isBefore(today);
}

/// The status a reader should hear. A live-looking "Sent" on a quotation nobody
/// can order from is the defect this card fixes.
String _statusLabel(SalesQuotation item, DateTime now) =>
    _hasExpired(item, now) ? 'Expired' : _quoteStatusLabel(item.status);

StatusTone _statusTone(SalesQuotation item, DateTime now) {
  if (_hasExpired(item, now)) return StatusTone.error;
  return switch (item.status) {
    SalesQuoteStatus.accepted => StatusTone.success,
    SalesQuoteStatus.sent => StatusTone.info,
    SalesQuoteStatus.expired => StatusTone.error,
    SalesQuoteStatus.draft => StatusTone.neutral,
  };
}

String _quoteStatusLabel(SalesQuoteStatus value) =>
    value.name[0].toUpperCase() + value.name.substring(1);
