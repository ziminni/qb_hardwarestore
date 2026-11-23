import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/sales_module.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_document_list_content.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_quotation_form_dialog.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Store Manager's quotations screen: a shell only (card M3). The list, the
/// search, the status chips and the empty and error states live in
/// [SalesDocumentListContent], which the sales orders screen shows too.
///
/// "New quotation" is BACK: it was removed in Phase 3 Task 0 because no endpoint
/// existed, and `POST /api/v1/quotations/` now does. This screen also closes the
/// loop the shop works in — a manager raises the sales order from a quotation,
/// and the cashier rings THAT order from the till's Orders button.
///
/// Nothing here writes a status: there is no accept endpoint, so a quotation
/// stays DRAFT until an order honours it.
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

  /// Opens the document sheet (decision D-02) and acts on what the reader picked.
  ///
  /// Reads the app-scoped catalogue once per tap to turn `variant_uom` ids into
  /// names. A missing catalogue is not an error: [variantUomName] falls back to
  /// the id.
  Future<void> _showQuotationSheet(
    BuildContext context,
    SalesQuotation item,
    DateTime now,
  ) async {
    final inventory = context.read<InventoryViewmodel?>();
    // A manager turns the promise into the order the till rings. The SERVER still
    // decides: `POST /api/v1/sales-orders/` runs its own guards.
    final canOrder = _mayManage(context);
    final action = await showSalesDocumentSheet(
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
      total: item.total,
      canCreateOrder: canOrder,
    );
    if (!mounted || action != SalesDocumentAction.createOrder) return;
    await _convertToOrder(item);
  }

  /// Whether this account may raise an order from a quotation at all.
  ///
  /// The role CODE decides (Phase 4 lesson: labels lie), through the areas the
  /// account HOLDS so a merged account keeps the action with no active area.
  bool _mayManage(BuildContext context) {
    final auth = context.read<AuthViewmodel?>();
    return auth?.hasAnyArea(const {'sales', 'admin'}) ?? false;
  }

  /// Raises a sales order from a quotation, after a confirmation that names the
  /// price rule and who rings it.
  ///
  /// Always allowed, even for a quotation that already has an order: the server
  /// keeps no such rule, and guessing at one here would either block a real
  /// second order or invent a state nothing maintains. The dialog says so
  /// instead, and the order carries its `quotation` link so the two stay
  /// traceable.
  Future<void> _convertToOrder(SalesQuotation item) async {
    final viewmodel = context.read<SalesModuleViewmodel>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create sales order'),
        content: Text(
          'Raise a sales order for ${item.customer} from ${item.number}?\n\n'
          'Prices are the agreed prices; the cashier rings it from Orders.\n\n'
          'If this quotation already has an order, a second one will be '
          'created.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('sq-confirm-order'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Create order'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // The quotation's customer and lines, at the prices already agreed: the order
    // is what the till will charge, so nothing is re-typed or re-priced here.
    final (number, refusal) = await viewmodel.createOrderWithNumber(
      SalesOrderDraft(
        customerId: item.customerId,
        quotationId: item.id,
        lines: [
          for (final line in item.items)
            SalesOrderLineDraft(
              variantUomId: line.variantUomId,
              qty: line.qty,
              unitPrice: line.unitPrice,
            ),
        ],
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(refusal?.message ?? 'Sales order $number created.'),
      ),
    );
  }

  /// Opens the create form and posts what it collected.
  ///
  /// The dialog posts through the viewmodel itself, because a refusal must land
  /// INSIDE the form with the input intact; only a success closes it, and then
  /// the viewmodel has already reloaded the list.
  Future<void> _openForm() async {
    final viewmodel = context.read<SalesModuleViewmodel>();
    final inventory = context.read<InventoryViewmodel?>();
    if (inventory != null && !inventory.hasLoaded) await inventory.load();
    if (!mounted) return;
    final number = await showDialog<String>(
      context: context,
      builder: (_) => SalesQuotationFormDialog(
        customers: viewmodel.customers,
        catalogue: inventory?.catalogue ?? const [],
        onSubmit: viewmodel.createQuotation,
      ),
    );
    if (number == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Quotation $number created.')));
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
      subtitle:
          'Formal price estimates for customers (does not reserve or deduct stock).',
      selectedNavigationIndex: 2,
      // The list owns the scrolling, so it builds only the rows on screen.
      scrollable: false,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A failed load left no customers to name and no fresh rows behind it,
          // so the form is offered only once the page has read what it needs.
          if (viewmodel.loadError == null)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _openForm,
                icon: const Icon(Icons.add),
                label: const Text('New quotation'),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          // The list takes the rest of the slot and scrolls its own rows.
          Expanded(
            child: SalesDocumentListContent(
              kind: SalesDocumentKind.quotation,
              rows: [for (final item in quotations) _row(item, now)],
              isLoading: viewmodel.isLoading,
              loadError: viewmodel.loadError,
              onRetry: viewmodel.load,
            ),
          ),
        ],
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
