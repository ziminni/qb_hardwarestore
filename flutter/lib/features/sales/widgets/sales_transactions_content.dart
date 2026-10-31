import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// Which role is reading the transaction list. The three screens that show it
/// (cashier history, store manager transactions, stock manager sales) were three
/// copies with three different column sets and three table styles; they are now
/// one list whose few real differences are named here.
enum SalesTransactionsRole {
  /// The cashier's own history: no Source column, and no View action because a
  /// row tap is the whole gesture.
  cashier,

  /// The store manager's transactions: Source is shown, and the row keeps a
  /// View action (the rows are also tappable).
  storeManager,

  /// The stock manager's sales: units out is the number that matters, money
  /// moves into the details sheet.
  stockManager,
}

/// The one transaction list, shared by the three role screens.
///
/// Owns only presentation state (the search text and the active status chip) and
/// reads the rows the page's viewmodel already loaded. It never fetches, so the
/// same widget cannot disagree with its page about what a sale is.
///
/// shortcut: the panel sits in the role shell's own scroll view, so every row is
/// built at once instead of lazily. Fine for the list the service loads (40 pages
/// capped); give it a bounded slot (an `Expanded` with `AppShell.scrollable`
/// false) if this list ever outgrows that.
class SalesTransactionsContent extends StatefulWidget {
  const SalesTransactionsContent({
    super.key,
    required this.role,
    required this.sales,
    this.isLoading = false,
    this.loadError,
    this.onRetry,
  });

  final SalesTransactionsRole role;

  /// The loaded sales, straight from the viewmodel. Returns are not in here:
  /// the viewmodel splits them out into their own list.
  final List<InventorySale> sales;

  final bool isLoading;
  final String? loadError;
  final VoidCallback? onRetry;

  @override
  State<SalesTransactionsContent> createState() =>
      _SalesTransactionsContentState();
}

class _SalesTransactionsContentState extends State<SalesTransactionsContent> {
  /// The chip that filters nothing.
  static const String _anyStatus = 'All';

  /// Chip labels, in the order they render. They are the status labels the
  /// badges use, so the same word means the same thing in both places.
  static const List<String> _statusChips = [
    _anyStatus,
    'Completed',
    'Refunded',
    'Void',
  ];

  String _query = '';
  String _status = _anyStatus;

  /// True once the reader has narrowed the list, which changes what "nothing to
  /// show" means: an empty system and an empty filter are different facts.
  bool get _filtered => _query.isNotEmpty || _status != _anyStatus;

  List<InventorySale> get _visible => [
    for (final sale in widget.sales)
      if (_matchesQuery(sale) && _matchesStatus(sale)) sale,
  ];

  bool _matchesQuery(InventorySale sale) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    final haystack = switch (widget.role) {
      // The stock manager looks sales up by what left the shelf, so the SKU is
      // searchable there and nowhere else.
      SalesTransactionsRole.stockManager =>
        '${sale.transactionNo} ${sale.customer} '
            '${sale.lines.map((line) => line.sku).join(' ')}',
      SalesTransactionsRole.cashier || SalesTransactionsRole.storeManager =>
        '${sale.transactionNo} ${sale.customer} ${sale.paymentMethod} '
            '${sale.cashier}',
    };
    return haystack.toLowerCase().contains(query);
  }

  bool _matchesStatus(InventorySale sale) => switch (_status) {
    'Completed' => sale.status == InventorySaleStatus.completed,
    'Refunded' => sale.status == InventorySaleStatus.refunded,
    'Void' => sale.status == InventorySaleStatus.voided,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterBar(
          searchHint: switch (widget.role) {
            SalesTransactionsRole.stockManager =>
              'Transaction, customer, or SKU',
            SalesTransactionsRole.cashier ||
            SalesTransactionsRole.storeManager =>
              'Transaction, customer, or payment',
          },
          onSearchChanged: (value) => setState(() => _query = value),
          options: _statusChips,
          selected: _status,
          onSelected: (chip) => setState(() => _status = chip),
        ),
        const SizedBox(height: AppSpacing.lg),
        LayoutBuilder(
          builder: (context, slot) {
            // DataPanel turns the table into cards on its own content width; the
            // View action only belongs to the table, because on a card the whole
            // card is the tap target.
            final cards =
                slot.maxWidth - AppPanel.chrome < DataPanel.cardBreakpoint;
            return DataPanel<InventorySale>(
              columns: _columns(withAction: !cards),
              rows: rows,
              emptyMessage: _filtered
                  ? 'No transactions match these filters.'
                  : 'No transactions found.',
              // The rows already on screen outlive a refresh, so the spinner is
              // only for a first load with nothing to show yet.
              isLoading: widget.isLoading && widget.sales.isEmpty,
              error: widget.loadError,
              onRetry: widget.onRetry,
              onRowTap: (sale) => _openDocument(context, sale),
              rowKey: (sale) => ValueKey(sale.transactionNo),
            );
          },
        ),
      ],
    );
  }

  List<DataPanelColumn<InventorySale>> _columns({required bool withAction}) {
    return switch (widget.role) {
      SalesTransactionsRole.cashier => [
        _transactionColumn(),
        _dateColumn(),
        _customerColumn(),
        _paymentColumn(),
        _totalColumn(),
      ],
      SalesTransactionsRole.storeManager => [
        _transactionColumn(),
        _dateColumn(),
        // Source rides under the customer rather than in a column of its own:
        // with six columns a seven digit total lost its last digits at 1100 px
        // (the plan's own complaint about this table), and "who, and where it
        // came from" reads as one fact anyway.
        _customerColumn(withSource: true),
        _totalColumn(),
        if (withAction)
          DataPanelColumn<InventorySale>(
            label: 'Action',
            cell: (sale) => Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _openDocument(context, sale),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('View'),
              ),
            ),
          ),
      ],
      SalesTransactionsRole.stockManager => [
        _transactionColumn(),
        _dateColumn(),
        DataPanelColumn<InventorySale>(
          label: 'Items',
          cell: (sale) => _text(formatCount(sale.lines.length)),
        ),
        DataPanelColumn<InventorySale>(
          label: 'Units out',
          numeric: true,
          cell: (sale) => _text(
            _quantity(sale.totalQuantity),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    };
  }

  /// Document number with its status under it.
  ///
  /// The badge rides in this column instead of a Status column of its own: a
  /// separate Status column pushed the manager's View action off a 1100 px
  /// window and squeezed every document number into an ellipsis, and the narrow
  /// card already lays the two out exactly like this.
  DataPanelColumn<InventorySale> _transactionColumn() {
    return DataPanelColumn<InventorySale>(
      label: 'Transaction',
      cell: (sale) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            sale.transactionNo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          StatusBadge(label: sale.status.label, tone: _tone(sale.status)),
        ],
      ),
    );
  }

  DataPanelColumn<InventorySale> _dateColumn() {
    return DataPanelColumn<InventorySale>(
      label: 'Date and time',
      // Two lines are what the format needs; one line in a narrow column would
      // cut the time off, which is the half that tells two sales apart.
      cell: (sale) => _text(formatDateTime(sale.date), maxLines: 2),
    );
  }

  DataPanelColumn<InventorySale> _customerColumn({bool withSource = false}) {
    return DataPanelColumn<InventorySale>(
      label: 'Customer',
      cell: (sale) => withSource
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(sale.customer, maxLines: 2),
                const SizedBox(height: 2),
                Text(
                  sale.source,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            )
          : _text(sale.customer, maxLines: 2),
    );
  }

  DataPanelColumn<InventorySale> _paymentColumn() {
    return DataPanelColumn<InventorySale>(
      label: 'Payment',
      cell: (sale) => _text(
        // The viewmodel writes a bare dash for a sale with no payment rows; a
        // word says the same thing and cannot be mistaken for a loaded value.
        sale.payments.isEmpty ? 'No payment' : sale.paymentMethod,
      ),
    );
  }

  DataPanelColumn<InventorySale> _totalColumn() {
    return DataPanelColumn<InventorySale>(
      label: 'Total',
      numeric: true,
      cell: (sale) => _text(formatPeso(sale.total)),
    );
  }

  Widget _text(String value, {int maxLines = 1, TextStyle? style}) {
    return Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style:
          style ?? const TextStyle(fontSize: 14, color: AppColors.textPrimary),
    );
  }

  StatusTone _tone(InventorySaleStatus status) => switch (status) {
    InventorySaleStatus.completed => StatusTone.success,
    InventorySaleStatus.refunded => StatusTone.warning,
    InventorySaleStatus.voided => StatusTone.error,
  };

  /// Quantities come from exact batch arithmetic, so a whole number drops its
  /// ".0" and gains thousands separators; a fractional one keeps its decimals.
  String _quantity(double value) =>
      value % 1 == 0 ? formatCount(value.toInt()) : salesQty(value);

  /// The whole document, read-only. Every role gets the same sheet: the lines,
  /// how it was paid, who rang it and the total. Only the manager also needs
  /// where the sale came from, which the cashier's page omits.
  void _openDocument(BuildContext context, InventorySale sale) {
    showSalesDocumentSheet(
      context,
      title: sale.transactionNo,
      fields: [
        ('Date', formatDateTime(sale.date)),
        ('Customer', sale.customer),
        ('Cashier', sale.cashier),
        if (widget.role == SalesTransactionsRole.storeManager)
          ('Source', sale.source),
        ('Items', formatCount(sale.lines.length)),
        ('Units out', _quantity(sale.totalQuantity)),
        for (final payment in sale.payments)
          (
            'Payment (${TenderMethod.labelFor(payment.method)})',
            formatPeso(payment.amount),
          ),
        ('Status', sale.status.label),
      ],
      lines: [
        for (final line in sale.lines)
          SalesDocumentLine(
            name: line.productName,
            qty: line.quantity,
            unitPrice: line.unitPrice,
          ),
      ],
      total: formatPeso(sale.total),
    );
  }
}
