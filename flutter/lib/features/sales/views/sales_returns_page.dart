import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/returns_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_unlinked_return_dialog.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Store Manager's Returns and refunds screen (card M5).
///
/// Two jobs, one screen: review every customer return, and post the one
/// correction a cashier cannot — a return with no original sale. The list is the
/// shared [DataPanel] in the same shape as the stock manager's Returns screen
/// (card K9): the document number carries its status underneath, the original
/// sale reads "Not linked" when the wire has none, and the reason lives in the
/// read-only document sheet instead of stretching the table.
///
/// The page owns presentation state only (the search text and the status chip)
/// and never fetches: the list is whatever `InventorySalesViewmodel.returns`
/// already loaded, so this screen cannot disagree with the dashboard about how
/// many returns were completed.
class SalesReturnsPage extends StatefulWidget {
  const SalesReturnsPage({
    super.key,
    this.returnsService,
    this.customerService,
    this.productsService,
  });

  /// Injected by tests so the unlinked dialog can post WITHOUT a server.
  final ReturnsService? returnsService;
  final CustomerService? customerService;
  final ProductsService? productsService;

  @override
  State<SalesReturnsPage> createState() => _SalesReturnsPageState();
}

class _SalesReturnsPageState extends State<SalesReturnsPage> {
  /// The chip that filters nothing.
  static const String _anyStatus = 'All';

  /// The statuses a posted return can carry. The viewmodel maps the wire's
  /// COMPLETED and REFUNDED onto Completed and VOID onto Rejected, so these
  /// three are the only ones reachable from this list: the server has no
  /// pending-return state, and the dashboard's zero pending count is true.
  static const List<String> _statusChips = [
    _anyStatus,
    'Completed',
    'Rejected',
  ];

  /// Said instead of the dash the viewmodel writes for a return the wire did not
  /// tie to an original sale (D18: a word, never a dash).
  static const String _notLinked = 'Not linked';

  /// The one manager-only act on this page, and how a reader knows it is his and
  /// nobody else's.
  static const String _managerOnlyNote = 'Manager only: no original sale';

  String _query = '';
  String _status = _anyStatus;

  /// True once the reader has narrowed the list, which changes what "nothing to
  /// show" means: an empty store and an empty filter are different facts.
  bool get _filtered => _query.trim().isNotEmpty || _status != _anyStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventorySalesViewmodel>().load();
    });
  }

  /// This page is the CUSTOMER returns page: a supplier return is stock going
  /// back, which the stock manager's screen reads.
  List<InventoryReturn> _visible(List<InventoryReturn> returns) => [
    for (final item in returns)
      if (item.type == InventoryReturnType.customer &&
          _matchesQuery(item) &&
          _matchesStatus(item))
        item,
  ];

  /// The manager looks a return up by the document, the sale it reverses, or the
  /// item that came back.
  bool _matchesQuery(InventoryReturn item) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = [
      item.reference,
      item.relatedReference,
      item.reason,
      for (final line in item.lines) line.sku,
    ].join(' ');
    return haystack.toLowerCase().contains(query);
  }

  bool _matchesStatus(InventoryReturn item) => switch (_status) {
    'Completed' => item.status == InventoryReturnStatus.completed,
    'Rejected' => item.status == InventoryReturnStatus.rejected,
    _ => true,
  };

  /// The original sale, or a word when the wire has none.
  String _related(InventoryReturn item) =>
      item.relatedReference.isEmpty || item.relatedReference == '—'
      ? _notLinked
      : item.relatedReference;

  /// The unlinked correction is a manager act: the server 403s anyone else
  /// with `UNLINKED_RETURN_FORBIDDEN`, so the button is not offered to them.
  /// Compared by role CODE, never label (Phase 4 lesson).
  bool _mayPostUnlinked(BuildContext context) {
    final role = context.watch<AuthViewmodel>().roleName;
    // 'admin' stays although [AppRoutes.redirectFor] keeps an admin out of
    // /sales today: the server admits it (`IsManagerRole`), and a role rule
    // change must not silently take the action away. Drop it with the route.
    return role == 'sales' || role == 'admin';
  }

  void _openUnlinkedDialog(
    BuildContext context,
    InventorySalesViewmodel viewmodel,
  ) {
    showDialog<void>(
      context: context,
      builder: (_) => UnlinkedReturnDialog(
        returnsService: widget.returnsService ?? ReturnsService(),
        customerService: widget.customerService ?? CustomerService(),
        productsService: widget.productsService ?? ProductsService(),
        onPosted: viewmodel.load,
      ),
    );
  }

  /// Opens the read-only return details sheet — the same document sheet the
  /// transactions page uses (decision D-02 pattern).
  ///
  /// A posted return is immutable, so this sheet only reads: the original sale
  /// it reverses, every line with its quantity, the reason, the refund and who
  /// processed it.
  void _showReturnSheet(InventoryReturn item) {
    showSalesDocumentSheet(
      context,
      title: item.reference,
      fields: [
        ('Original sale', _related(item)),
        ('Date', formatDateTime(item.date)),
        ('Cashier', item.processedBy),
        ('Reason', item.reason),
        ('Status', item.status.label),
      ],
      lines: [
        for (final line in item.lines)
          SalesDocumentLine(
            // The wire carries no product names, only the selling-unit code
            // (same limitation the transactions sheet states), so the code is
            // the line name rather than an invented one.
            name: line.productName,
            qty: line.quantity,
            unitPrice: line.unitPrice,
          ),
      ],
      total: formatPeso(item.total),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<InventorySalesViewmodel>();
    final returns = viewmodel.returns;
    final rows = _visible(returns);
    final failure = viewmodel.loadError;

    return SalesSkeletonLayout(
      title: 'Returns & Refunds',
      subtitle: 'Review customer returns, replacements, and refund outcomes.',
      selectedNavigationIndex: 5,
      // The list owns the scrolling: a bounded slot lets the panel build only
      // the rows on screen, and a store collects returns for years.
      scrollable: false,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // "New customer return" is GONE (Phase 3 Task 0): a cashier returns
          // from the till's Returns tab. The manager's unlinked correction is
          // the one write here, and it is the only filled button on the page.
          if (_mayPostUnlinked(context)) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    _managerOnlyNote,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () => _openUnlinkedDialog(context, viewmodel),
                  icon: const Icon(Icons.assignment_return_outlined, size: 18),
                  label: const Text('Unlinked return'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          FilterBar(
            searchHint: 'Return, original sale, or item code',
            onSearchChanged: (value) => setState(() => _query = value),
            options: _statusChips,
            selected: _status,
            onSelected: (chip) => setState(() => _status = chip),
          ),
          // A refresh that fails keeps the rows already on screen, so the
          // failure is named above them instead of replacing them.
          if (failure != null && rows.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: failure, onRetry: viewmodel.load),
          ],
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: LayoutBuilder(
              builder: (context, slot) {
                // DataPanel turns the table into cards on its own content width;
                // the View action only belongs to the table, because on a card
                // the whole card is the tap target.
                final cards =
                    slot.maxWidth - AppPanel.chrome < DataPanel.cardBreakpoint;
                return DataPanel<InventoryReturn>(
                  columns: _columns(withAction: !cards),
                  rows: rows,
                  emptyMessage: _filtered
                      ? 'No returns match these filters.'
                      : 'No customer returns available.',
                  // The spinner is for a first load with nothing to show yet:
                  // with rows on screen it would hide them.
                  isLoading: viewmodel.isLoading && returns.isEmpty,
                  error: returns.isEmpty ? failure : null,
                  onRetry: viewmodel.load,
                  onRowTap: _showReturnSheet,
                  rowKey: (item) => ValueKey(item.reference),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<DataPanelColumn<InventoryReturn>> _columns({
    required bool withAction,
  }) => [
    DataPanelColumn<InventoryReturn>(
      label: 'Return',
      // Two shares: the document number is what a reader looks for first, and
      // the badge underneath is one short word.
      flex: 2,
      cell: (item) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.reference,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          StatusBadge(label: item.status.label, tone: _tone(item.status)),
        ],
      ),
    ),
    DataPanelColumn<InventoryReturn>(
      label: 'Date and time',
      flex: 2,
      // Two lines are what the format needs; one line in a narrow column would
      // cut the time off, which is the half that tells two returns apart.
      cell: (item) => _text(formatDateTime(item.date), maxLines: 2),
    ),
    DataPanelColumn<InventoryReturn>(
      label: 'Original sale',
      flex: 2,
      cell: (item) => _text(_related(item)),
    ),
    DataPanelColumn<InventoryReturn>(
      label: 'Items',
      numeric: true,
      cell: (item) => _text(formatCount(item.lines.length)),
    ),
    if (withAction)
      DataPanelColumn<InventoryReturn>(
        // Action is a button, not a name: it gets one share so the columns that
        // carry data keep the room.
        label: 'Action',
        cell: (item) => Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => _showReturnSheet(item),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('View'),
          ),
        ),
      ),
  ];

  Widget _text(String value, {int maxLines = 1, TextStyle? style}) {
    return Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style:
          style ?? const TextStyle(fontSize: 14, color: AppColors.textPrimary),
    );
  }

  StatusTone _tone(InventoryReturnStatus status) => switch (status) {
    InventoryReturnStatus.completed ||
    InventoryReturnStatus.approved => StatusTone.success,
    InventoryReturnStatus.pending => StatusTone.warning,
    InventoryReturnStatus.rejected => StatusTone.error,
  };
}
