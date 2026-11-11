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
import 'package:client/core/time/app_clock.dart';
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
/// Owns only presentation state (the search text, the active status chip and the
/// manager's date range) and reads the rows the page's viewmodel already loaded.
/// It never fetches, so the same widget cannot disagree with its page about what
/// a sale is.
///
/// The page gives it a bounded slot (`AppShell.scrollable` false, this widget's
/// own `Expanded`), so the panel scrolls its rows and builds only the visible
/// ones: the service can load 40 pages, and eager layout built every row of
/// them at first paint.
class SalesTransactionsContent extends StatefulWidget {
  const SalesTransactionsContent({
    super.key,
    required this.role,
    required this.sales,
    this.isLoading = false,
    this.loadError,
    this.onRetry,
    this.now,
  });

  final SalesTransactionsRole role;

  /// The loaded sales, straight from the viewmodel. Returns are not in here:
  /// the viewmodel splits them out into their own list.
  final List<InventorySale> sales;

  final bool isLoading;
  final String? loadError;
  final VoidCallback? onRetry;

  /// The clock the date range chips read. Injected so a test can fix "today"
  /// instead of following the wall clock into another week. Nullable because a
  /// default value has to be const, so it falls back to `clock.now`.
  final DateTime Function()? now;

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

  /// The date range that filters nothing.
  static const String _anyDate = 'All dates';

  /// The manager's date range, over the rows already loaded (the plan's answer
  /// to "review one day or one refund"). "All dates" rather than a second "All"
  /// next to the status chips: two chips with the same word, one above the
  /// other, would be a guessing game.
  static const List<String> _dateChips = [
    _anyDate,
    'Today',
    'This week',
    'This month',
  ];

  /// Says out loud that a range is a client filter, not a fresh fetch.
  static const String _dateCaption =
      'Date ranges count only the transactions already loaded.';

  String _query = '';
  String _status = _anyStatus;
  String _date = _anyDate;

  bool get _dateFiltered => _date != _anyDate;

  /// True once the reader has narrowed the list, which changes what "nothing to
  /// show" means: an empty system and an empty filter are different facts.
  bool get _filtered =>
      _query.isNotEmpty || _status != _anyStatus || _dateFiltered;

  List<InventorySale> get _visible {
    // Read once per build: a range computed from a moving clock could narrow
    // halfway through the list at midnight.
    final now = widget.now?.call() ?? appClock.now();
    return [
      for (final sale in widget.sales)
        if (_matchesQuery(sale) &&
            _matchesStatus(sale) &&
            _matchesDate(sale, now))
          sale,
    ];
  }

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

  /// The manager's date range over the loaded rows. Weeks start on Monday and
  /// every comparison is local time, because the dates the reader sees are.
  bool _matchesDate(InventorySale sale, DateTime now) => switch (_date) {
    'Today' => _sameDay(sale.date, now),
    'This week' => _inWeekOf(sale.date, now),
    'This month' => sale.date.year == now.year && sale.date.month == now.month,
    _ => true,
  };

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _inWeekOf(DateTime date, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    // weekday: Monday is 1, Sunday is 7.
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));
    return !date.isBefore(monday) && date.isBefore(nextMonday);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final storeManager = widget.role == SalesTransactionsRole.storeManager;
    return Column(
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
          // The date range is the store manager's filter: a cashier reads the
          // till's own shift, and the stock manager reads what left the shelf.
          extraOptions: storeManager ? _dateChips : const <String>[],
          extraSelected: _date,
          onExtraSelected: (chip) => setState(() => _date = chip),
        ),
        if (storeManager) ...[
          const SizedBox(height: AppSpacing.sm),
          const Text(
            _dateCaption,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        // The panel takes the height the page has left over, which is what lets
        // it scroll its own rows and build only the ones on screen.
        Expanded(
          child: LayoutBuilder(
            builder: (context, slot) {
              // DataPanel turns the table into cards on its own content width;
              // the View action only belongs to the table, because on a card
              // the whole card is the tap target.
              final cards =
                  slot.maxWidth - AppPanel.chrome < DataPanel.cardBreakpoint;
              return DataPanel<InventorySale>(
                title: 'Transactions',
                count: rows.length,
                columns: _columns(withAction: !cards),
                rows: rows,
                emptyMessage: _filtered
                    ? 'No transactions match these filters.'
                    : 'No transactions found.',
                // The rows already on screen outlive a refresh, so the spinner
                // is only for a first load with nothing to show yet.
                isLoading: widget.isLoading && widget.sales.isEmpty,
                error: widget.loadError,
                onRetry: widget.onRetry,
                onRowTap: (sale) => _openDocument(context, sale),
                rowKey: (sale) => ValueKey(sale.transactionNo),
              );
            },
          ),
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
        // Source and payment ride under the customer rather than in columns of
        // their own: with six columns a seven digit total lost its last digits
        // at 1100 px (the plan's own complaint about this table), and "who,
        // where it came from, and how it was paid" reads as one fact anyway.
        // The Payment column the plan asks for lost the money column its digits
        // when it was tried as a seventh column, so the value rides here.
        _customerColumn(withSource: true, withPayment: true, flex: 3),
        _totalColumn(),
        if (withAction)
          DataPanelColumn<InventorySale>(
            // Action is a button, not a name: it gets one share so Customer can
            // take three and stop ellipsizing while a short column sits empty.
            label: 'Action',
            flex: 1,
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
  ///
  /// Two shares, like the customer: the document number is what a reader looks
  /// for first, and a single share cut it to an ellipsis beside columns holding
  /// one short word.
  DataPanelColumn<InventorySale> _transactionColumn({int flex = 2}) {
    return DataPanelColumn<InventorySale>(
      label: 'Transaction',
      flex: flex,
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
      flex: 2,
      // Two lines are what the format needs; one line in a narrow column would
      // cut the time off, which is the half that tells two sales apart.
      cell: (sale) => _text(formatDateTime(sale.date), maxLines: 2),
    );
  }

  /// The customer, with the facts that belong to them underneath: where the
  /// sale came from (manager) and how it was paid (manager).
  DataPanelColumn<InventorySale> _customerColumn({
    bool withSource = false,
    bool withPayment = false,
    int flex = 2,
  }) {
    return DataPanelColumn<InventorySale>(
      label: 'Customer',
      flex: flex,
      cell: (sale) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(sale.customer, maxLines: 2),
          if (withSource) ...[const SizedBox(height: 2), _caption(sale.source)],
          if (withPayment) ...[
            const SizedBox(height: 2),
            _caption(_paymentOf(sale)),
          ],
        ],
      ),
    );
  }

  DataPanelColumn<InventorySale> _paymentColumn({int flex = 2}) {
    return DataPanelColumn<InventorySale>(
      label: 'Payment',
      flex: flex,
      cell: (sale) => _text(_paymentOf(sale)),
    );
  }

  /// How the sale was paid, or a word for the sales that were not.
  ///
  /// The viewmodel writes a bare dash for a sale with no payment rows; a word
  /// says the same thing and cannot be mistaken for a loaded value.
  String _paymentOf(InventorySale sale) =>
      sale.payments.isEmpty ? 'No payment' : sale.paymentMethod;

  /// Two shares, not one: money is what the manager scans down, and a single
  /// share clipped a seven digit total beside columns holding one word.
  DataPanelColumn<InventorySale> _totalColumn() {
    return DataPanelColumn<InventorySale>(
      label: 'Total',
      numeric: true,
      flex: 2,
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

  /// The quieter second line under a name: the source and the payment method.
  Widget _caption(String value) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
      total: sale.total,
    );
  }
}
