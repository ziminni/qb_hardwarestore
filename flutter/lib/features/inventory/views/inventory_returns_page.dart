import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The stocker's Returns tab (decision D-01): a READ-ONLY list of transactions
/// whose `source` is `RETURN`.
///
/// Why read-only: the `inventory` role is granted GET on `/api/v1/transactions/`
/// by `IsPOSOrReadOnly`, so listing returns costs no backend work, while
/// initiating one needs a `process_return` flow that does not exist yet (map
/// fog). The viewmodel is the app-scoped `InventorySalesViewmodel`, the same one
/// the sales screens use, so a return cannot disagree with itself on two screens.
///
/// The list is the shared `DataPanel` in the stock view (card K9): the document
/// number carries its status underneath, "Units back" is the emphasised number
/// because stock coming back is what this role reads, and the money lives in the
/// read-only document sheet a row tap opens.
class InventoryReturnsPage extends StatefulWidget {
  const InventoryReturnsPage({super.key});

  @override
  State<InventoryReturnsPage> createState() => _InventoryReturnsPageState();
}

class _InventoryReturnsPageState extends State<InventoryReturnsPage> {
  /// The chip that filters nothing.
  static const String _anyStatus = 'All';

  /// The statuses a posted return can carry. The viewmodel maps the wire's
  /// COMPLETED and REFUNDED onto Completed and VOID onto Rejected, so these
  /// three are the only ones reachable from this list.
  static const List<String> _statusChips = [
    _anyStatus,
    'Completed',
    'Rejected',
  ];

  /// Said instead of the dash the viewmodel writes for a return the wire did not
  /// tie to an original sale (D18: a word, never a dash).
  static const String _notLinked = 'Not linked';

  String _query = '';
  String _status = _anyStatus;

  /// True once the reader has narrowed the list, which changes what "nothing to
  /// show" means: an empty store and an empty filter are different facts.
  bool get _filtered => _query.trim().isNotEmpty || _status != _anyStatus;

  @override
  void initState() {
    super.initState();
    // The provider is app-scoped (see main.dart), so it outlives this page and
    // is read after the first frame rather than during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventorySalesViewmodel>().load();
    });
  }

  List<InventoryReturn> _visible(List<InventoryReturn> returns) => [
    for (final item in returns)
      if (_matchesQuery(item) && _matchesStatus(item)) item,
  ];

  /// The stock manager looks a return up by the document, the sale it reverses,
  /// or the item that came back.
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

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<InventorySalesViewmodel>();
    final returns = viewmodel.returns;
    final rows = _visible(returns);
    final failure = viewmodel.loadError;

    return InventorySkeletonLayout(
      title: 'Returns & Refunds',
      subtitle: 'Review stock returned through customer refunds.',
      selectedNavigationIndex: 10,
      // The list owns the scrolling: a bounded slot lets the panel build only
      // the rows on screen, and the page can hold a return for years.
      scrollable: false,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterBar(
            searchHint: 'Return, original sale, or SKU',
            onSearchChanged: (value) => setState(() => _query = value),
            options: _statusChips,
            selected: _status,
            onSelected: (chip) => setState(() => _status = chip),
          ),
          // A refresh that fails keeps the rows already on screen, so the
          // failure is named above them instead of replacing them.
          if (failure != null && returns.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: failure, onRetry: viewmodel.load),
          ],
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: DataPanel<InventoryReturn>(
              columns: _columns,
              rows: rows,
              emptyMessage: _filtered
                  ? 'No returns match these filters.'
                  : 'No returns recorded.',
              // The spinner is for a first load with nothing to show yet: with
              // rows on screen it would hide them.
              isLoading: viewmodel.isLoading && returns.isEmpty,
              error: returns.isEmpty ? failure : null,
              onRetry: viewmodel.load,
              onRowTap: (item) => _openDocument(context, item),
              rowKey: (item) => ValueKey(item.reference),
            ),
          ),
        ],
      ),
    );
  }

  List<DataPanelColumn<InventoryReturn>> get _columns => [
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
      cell: (item) => _text(formatCount(item.lines.length)),
    ),
    DataPanelColumn<InventoryReturn>(
      label: 'Units back',
      numeric: true,
      // One share like the sales list: a count of units is short, and the room
      // belongs to the document number.
      cell: (item) => _text(
        _quantity(item.quantity),
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
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

  /// Quantities come from exact batch arithmetic, so a whole number drops its
  /// ".0" and gains thousands separators; a fractional one keeps its decimals.
  String _quantity(double value) =>
      value % 1 == 0 ? formatCount(value.toInt()) : salesQty(value);

  /// The whole document, read-only: what came back, against which sale, why, and
  /// what it was worth. A posted return is immutable, so there is nothing here
  /// to press (decision D-02).
  void _openDocument(BuildContext context, InventoryReturn item) {
    showSalesDocumentSheet(
      context,
      title: item.reference,
      fields: [
        ('Original sale', _related(item)),
        ('Date', formatDateTime(item.date)),
        ('Type', item.type.label),
        ('Reason', item.reason),
        ('Processed by', item.processedBy),
        ('Units back', _quantity(item.quantity)),
        ('Status', item.status.label),
      ],
      lines: [
        for (final line in item.lines)
          SalesDocumentLine(
            // The wire carries no product names, only the selling-unit code
            // (the same limitation the transactions sheet states), so the code
            // is the line name rather than an invented one.
            name: line.productName,
            qty: line.quantity,
            unitPrice: line.unitPrice,
          ),
      ],
      total: formatPeso(item.total),
    );
  }
}
