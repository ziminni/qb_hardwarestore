import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    this.orTracking = false,
    this.onAttachOr,
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

  /// Groups the rows by whether the paper OR number is on the slip, and offers
  /// [onAttachOr] on the rows that have none. Off everywhere except the till's
  /// OR-tagged tab, which is the screen whose whole job this is.
  final bool orTracking;

  /// Starts the tagging for one row. The page reloads when it returns, because
  /// the server stores the number.
  final VoidCallback? onAttachOr;

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
    'Pending Pickup',
    'Refunded',
    'Void',
  ];

  /// The OR chips REPLACE the status chips when [SalesTransactionsContent
  /// .orTracking] is on: two chip groups cannot both carry an "All", and the
  /// question this tab answers is the OR one.
  static const List<String> _orChips = [_anyStatus, 'OR-tagged', 'Untagged'];

  /// The date range that filters nothing.
  static const String _anyDate = 'All dates';

  static const String _customDate = 'Custom range';

  /// The manager's date range, over the rows already loaded (the plan's answer
  /// to "review one day or one refund"). "All dates" rather than a second "All"
  /// next to the status chips: two chips with the same word, one above the
  /// other, would be a guessing game.
  static const List<String> _dateChips = [
    _anyDate,
    'Today',
    'Yesterday',
    'This week',
    'This month',
    _customDate,
  ];

  /// Says out loud that a range is a client filter, not a fresh fetch.
  static const String _dateCaption =
      'Date ranges count only the transactions already loaded.';

  String _query = '';
  String _status = _anyStatus;
  String _or = _anyStatus;
  String _date = _anyDate;
  DateTimeRange? _customRange;

  /// True when the paper OR number is on the slip.
  static bool _isTagged(InventorySale sale) =>
      sale.invoiceNo != null && sale.invoiceNo!.isNotEmpty;

  bool get _dateFiltered => _date != _anyDate;

  Future<void> _pickCustomDateRange() async {
    final now = widget.now?.call() ?? appClock.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      currentDate: now,
      initialDateRange:
          _customRange ??
          DateTimeRange(
            start: DateTime(
              now.year,
              now.month,
              now.day,
            ).subtract(const Duration(days: 7)),
            end: DateTime(now.year, now.month, now.day),
          ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customRange = picked;
      _date = _customDate;
    });
  }

  /// True once the reader has narrowed the list, which changes what "nothing to
  /// show" means: an empty system and an empty filter are different facts.
  bool get _filtered =>
      _query.isNotEmpty ||
      _status != _anyStatus ||
      _dateFiltered ||
      (widget.orTracking && _or != _anyStatus);

  List<InventorySale> get _visible {
    // Read once per build: a range computed from a moving clock could narrow
    // halfway through the list at midnight.
    final now = widget.now?.call() ?? appClock.now();
    return [
      for (final sale in widget.sales)
        if (_matchesQuery(sale) &&
            _matchesStatus(sale) &&
            _matchesOr(sale) &&
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
        '${sale.transactionNo} ${sale.orNumber} ${sale.customer} '
            '${sale.lines.map((line) => line.sku).join(' ')}',
      SalesTransactionsRole.cashier || SalesTransactionsRole.storeManager =>
        '${sale.transactionNo} ${sale.orNumber} ${sale.customer} '
            '${sale.paymentMethod} ${sale.cashier}',
    };
    return haystack.toLowerCase().contains(query);
  }

  bool _matchesStatus(InventorySale sale) => switch (_status) {
    'Completed' =>
      sale.status == InventorySaleStatus.completed && !sale.isAwaitingBodega,
    'Pending Pickup' => sale.isAwaitingBodega,
    'Refunded' => sale.status == InventorySaleStatus.refunded,
    'Void' => sale.status == InventorySaleStatus.voided,
    _ => true,
  };

  bool _matchesOr(InventorySale sale) => switch (_or) {
    'OR-tagged' => _isTagged(sale),
    'Untagged' => !_isTagged(sale),
    _ => true,
  };

  /// The manager's date range over the loaded rows. Weeks start on Monday and
  /// every comparison is local time, because the dates the reader sees are.
  bool _matchesDate(InventorySale sale, DateTime now) {
    final localDate = sale.date.toLocal();
    final localNow = now.toLocal();
    return switch (_date) {
      'Today' => _sameDay(localDate, localNow),
      'Yesterday' => _sameDay(
        localDate,
        DateTime(
          localNow.year,
          localNow.month,
          localNow.day,
        ).subtract(const Duration(days: 1)),
      ),
      'This week' => _inWeekOf(localDate, localNow),
      'This month' =>
        localDate.year == localNow.year && localDate.month == localNow.month,
      _customDate => _inCustomRange(localDate),
      _ => true,
    };
  }

  bool _inCustomRange(DateTime localDate) {
    final range = _customRange;
    if (range == null) return true;
    final day = DateTime(localDate.year, localDate.month, localDate.day);
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }

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
    final showDateFilters =
        widget.role == SalesTransactionsRole.storeManager ||
        widget.role == SalesTransactionsRole.cashier;
    // The OR tab asks its own question, so it swaps the status chips for the OR
    // ones instead of stacking a second "All" under them.
    final chipLabel = widget.orTracking ? 'OR' : 'Status';
    final chips = widget.orTracking ? _orChips : _statusChips;
    final chipSelected = widget.orTracking ? _or : _status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterBar(
          searchHint: switch (widget.role) {
            SalesTransactionsRole.stockManager =>
              'Transaction, OS #, customer, or SKU',
            SalesTransactionsRole.cashier ||
            SalesTransactionsRole.storeManager =>
              'Transaction, OS #, OR #, customer, or payment',
          },
          onSearchChanged: (value) => setState(() => _query = value),
          optionsLabel: chipLabel,
          options: chips,
          selected: chipSelected,
          onSelected: (chip) => setState(() {
            if (widget.orTracking) {
              _or = chip;
            } else {
              _status = chip;
            }
          }),
          extraOptionsLabel: showDateFilters ? 'Date' : null,
          extraOptions: showDateFilters ? _dateChips : const <String>[],
          extraSelected: _date,
          onExtraSelected: (chip) {
            if (chip == _customDate) {
              _pickCustomDateRange();
            } else {
              setState(() => _date = chip);
            }
          },
        ),
        if (showDateFilters) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _date == _customDate && _customRange != null
                    ? 'Custom range: ${formatDate(_customRange!.start)} – ${formatDate(_customRange!.end)} (${rows.length} shown)'
                    : _dateCaption,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: _date == _customDate && _customRange != null
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: _date == _customDate && _customRange != null
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
              if (_date == _customDate && _customRange != null) ...[
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _pickCustomDateRange,
                  child: const Text('Change dates'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => setState(() {
                    _date = _anyDate;
                    _customRange = null;
                  }),
                  child: const Text('Clear range'),
                ),
              ],
            ],
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
        // The OR tab's whole job: tag the slip that has no number yet. On the
        // card layout too, where the row tap opens the document instead.
        if (widget.onAttachOr != null)
          DataPanelColumn<InventorySale>(
            label: 'Action',
            flex: 1,
            cell: (sale) => _isTagged(sale)
                ? const SizedBox.shrink()
                : TextButton(
                    key: ValueKey('attach-or-${sale.transactionNo}'),
                    onPressed: widget.onAttachOr,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Attach'),
                  ),
          ),
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
          if (sale.orNumber.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              sale.orNumber.toUpperCase().startsWith('OS') ||
                      sale.orNumber.toUpperCase().startsWith('OR')
                  ? sale.orNumber
                  : 'OS ${sale.orNumber}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              StatusBadge(
                label: sale.displayStatusLabel,
                tone: _displayTone(sale),
              ),
              if (sale.invoiceNo != null && sale.invoiceNo!.isNotEmpty)
                StatusBadge(
                  label: 'OR ${sale.invoiceNo}',
                  tone: StatusTone.info,
                ),
              if (sale.bodegaBadgeLabel != null)
                StatusBadge(
                  label: sale.bodegaBadgeLabel!,
                  tone: sale.isBodegaReleased
                      ? StatusTone.success
                      : StatusTone.warning,
                ),
            ],
          ),
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
          if (!withSource && sale.lines.isNotEmpty) ...[
            const SizedBox(height: 2),
            _caption(
              '${formatCount(sale.lines.length)} item${sale.lines.length == 1 ? '' : 's'}'
              '${sale.cashier.isNotEmpty ? ' · ${sale.cashier}' : ''}',
            ),
          ],
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
      cell: (sale) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(_paymentOf(sale)),
          if (sale.discountAmount > 0) ...[
            const SizedBox(height: 2),
            _caption('Discount -${formatPeso(sale.discountAmount)}'),
          ] else if (sale.creditSale) ...[
            const SizedBox(height: 2),
            _caption('Utang / credit price'),
          ],
        ],
      ),
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

  StatusTone _displayTone(InventorySale sale) {
    if (sale.isAwaitingBodega) return StatusTone.warning;
    return switch (sale.status) {
      InventorySaleStatus.completed => StatusTone.success,
      InventorySaleStatus.refunded => StatusTone.warning,
      InventorySaleStatus.voided => StatusTone.error,
    };
  }

  /// Quantities come from exact batch arithmetic, so a whole number drops its
  /// ".0" and gains thousands separators; a fractional one keeps its decimals.
  String _quantity(double value) =>
      value % 1 == 0 ? formatCount(value.toInt()) : salesQty(value);

  /// The whole document, read-only. Every role gets the same sheet: the lines,
  /// how it was paid, who rang it and the total. Only the manager also needs
  /// where the sale came from, which the cashier's page omits.
  ///
  /// Watches [InventorySalesViewmodel] when present so an open sheet stays
  /// live-synced if Bodega releases the pickup while the cashier is viewing it.
  void _openDocument(BuildContext context, InventorySale initialSale) {
    showModalBottomSheet<SalesDocumentAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        InventorySalesViewmodel? vm;
        try {
          vm = Provider.of<InventorySalesViewmodel>(sheetContext);
        } on ProviderNotFoundException {
          vm = null;
        }
        final sale =
            vm?.sales
                .where((s) => s.transactionNo == initialSale.transactionNo)
                .firstOrNull ??
            initialSale;
        return SalesDocumentSheet(
          title: sale.transactionNo,
          fields: [
            if (sale.orNumber.isNotEmpty) ('Order Slip (OS)', sale.orNumber),
            // Store-ops Phase 1: the paper BIR OR's invoice no., when one was
            // attached. An untagged sale shows no row rather than a blank one.
            if (sale.invoiceNo != null && sale.invoiceNo!.isNotEmpty)
              ('OR Invoice No.', sale.invoiceNo!),
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
            if (sale.creditSale) ('Pricing', 'Credit price (utang)'),
            if (sale.bodegaDetailLabel != null)
              ('Bodega pickup', sale.bodegaDetailLabel!),
            // Phase 4 F4: the discount and its reason, then the VAT split the server
            // computed. A non-VAT store says so instead of printing two zeroes.
            if (sale.discountAmount > 0)
              (
                sale.discountReason.trim().isEmpty
                    ? 'Discount'
                    : 'Discount (${sale.discountReason})',
                formatPeso(sale.discountAmount),
              ),
            if (sale.paymentFee > 0)
              ('Payment fee', formatPeso(sale.paymentFee)),
            if (sale.vatRegistered) ...[
              ('Vatable sales', formatPeso(sale.vatableSales)),
              ('VAT', formatPeso(sale.vatAmount)),
            ] else
              ('VAT', 'Non-VAT'),
            ('Status', sale.displayStatusLabel),
          ],
          lines: [
            for (final line in sale.lines)
              SalesDocumentLine(
                name: line.productName,
                qty: line.quantity,
                unitPrice: line.unitPrice,
              ),
          ],
          // The total bar is what the customer owed: the lines less the discount.
          total: sale.amountDue,
        );
      },
    );
  }
}
