import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// Which of the two sales documents a [SalesDocumentListContent] lists.
///
/// The two screens differ in three strings (the number column's heading, the
/// empty message and the date's prefix) and in whether a quotation's valid date
/// gets a column. Everything else is the same list.
enum SalesDocumentKind { quotation, order }

/// One document as the list draws it.
///
/// The pages map their own model ([SalesQuotation], [SalesOrderRecord]) into
/// this shape, which is the only place that knows a wire type: the list stays a
/// dumb renderer, and a quotation's "Expired" rule is decided where the
/// quotation is, not here.
class SalesDocumentRow {
  const SalesDocumentRow({
    required this.number,
    required this.customer,
    required this.date,
    required this.total,
    required this.statusLabel,
    required this.tone,
    required this.onOpen,
    this.validUntil,
  });

  final String number;
  final String customer;

  /// When the document was raised; the sheet calls it Created or Order date.
  final DateTime date;

  /// When the quotation stops holding. Null for a sales order, which has no
  /// such thing.
  final DateTime? validUntil;

  final double total;

  /// The status as a reader should hear it, which is not always the wire's
  /// word: a quotation past its valid date reads "Expired".
  final String statusLabel;

  final StatusTone tone;

  /// Opens the read-only document sheet.
  final VoidCallback onOpen;
}

/// The one document list behind the Store Manager's Quotations and Sales orders
/// screens (card M3).
///
/// Both screens were the same shape built twice: a raw table that scrolled
/// sideways at 1100 px, no search, no status filter, and a quotation past its
/// date indistinguishable from a live one. This widget is the whole screen body
/// for both, so the two cannot drift.
///
/// It owns presentation state only (the search text and the status chip) and
/// never fetches. The page gives it a bounded slot (`scrollable: false` on the
/// role shell), so the panel scrolls its own rows and builds only the visible
/// ones.
class SalesDocumentListContent extends StatefulWidget {
  const SalesDocumentListContent({
    super.key,
    required this.kind,
    required this.rows,
    this.isLoading = false,
    this.loadError,
    this.onRetry,
  });

  final SalesDocumentKind kind;
  final List<SalesDocumentRow> rows;
  final bool isLoading;
  final String? loadError;
  final VoidCallback? onRetry;

  @override
  State<SalesDocumentListContent> createState() =>
      _SalesDocumentListContentState();
}

class _SalesDocumentListContentState extends State<SalesDocumentListContent> {
  /// The chip that filters nothing.
  static const String _anyStatus = 'All';

  String _query = '';
  String _status = _anyStatus;

  /// The chip labels are the status words the badges use, so a chip and a row
  /// badge cannot describe the same document with two different words.
  List<String> get _statusChips => switch (widget.kind) {
    SalesDocumentKind.quotation => const [
      _anyStatus,
      'Draft',
      'Sent',
      'Accepted',
      'Expired',
    ],
    SalesDocumentKind.order => const [
      _anyStatus,
      'Confirmed',
      'Processing',
      'Ready',
      'Completed',
    ],
  };

  String get _searchHint => switch (widget.kind) {
    SalesDocumentKind.quotation => 'Quotation or customer',
    SalesDocumentKind.order => 'Order or customer',
  };

  bool get _filtered => _query.trim().isNotEmpty || _status != _anyStatus;

  /// "Nothing exists yet" and "these filters hide everything" are different
  /// facts, and the panel says whichever is true.
  String get _emptyMessage => switch (widget.kind) {
    SalesDocumentKind.quotation =>
      _filtered
          ? 'No quotations match these filters.'
          : 'No quotations available.',
    SalesDocumentKind.order =>
      _filtered
          ? 'No sales orders match these filters.'
          : 'No sales orders available.',
  };

  List<SalesDocumentRow> get _visible {
    final query = _query.trim().toLowerCase();
    return [
      for (final row in widget.rows)
        if ((_status == _anyStatus || row.statusLabel == _status) &&
            (query.isEmpty ||
                '${row.number} ${row.customer}'.toLowerCase().contains(query)))
          row,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    final failure = widget.loadError;
    // A first load that failed is ONE failure, and it is the panel's own error
    // state: an inbox icon under a banner would say "no quotations", which the
    // failed read has not established.
    final firstLoadFailed = failure != null && widget.rows.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilterBar(
          searchHint: _searchHint,
          onSearchChanged: (value) => setState(() => _query = value),
          options: _statusChips,
          selected: _status,
          onSelected: (chip) => setState(() => _status = chip),
        ),
        // A refresh that failed keeps the rows it already read, so the failure
        // is said out loud above them rather than replacing them.
        if (failure != null && !firstLoadFailed) ...[
          const SizedBox(height: AppSpacing.md),
          ErrorBanner(message: failure, onRetry: widget.onRetry),
        ],
        const SizedBox(height: AppSpacing.lg),
        // The panel takes the height the page has left over, which is what lets
        // it scroll its own rows and build only the ones on screen.
        Expanded(
          child: LayoutBuilder(
            builder: (context, slot) {
              // DataPanel turns the table into cards on its own content width.
              // The View action belongs to the table: on a card the whole card
              // is the tap target.
              final cards =
                  slot.maxWidth - AppPanel.chrome < DataPanel.cardBreakpoint;
              return DataPanel<SalesDocumentRow>(
                columns: _columns(withAction: !cards),
                rows: rows,
                emptyMessage: _emptyMessage,
                // The rows already on screen outlive a refresh, so the spinner
                // is only for a first load with nothing to show yet.
                isLoading: widget.isLoading && widget.rows.isEmpty,
                error: firstLoadFailed ? failure : null,
                onRetry: widget.onRetry,
                onRowTap: (row) => row.onOpen(),
                rowKey: (row) => ValueKey(row.number),
              );
            },
          ),
        ),
      ],
    );
  }

  List<DataPanelColumn<SalesDocumentRow>> _columns({required bool withAction}) {
    return [
      _numberColumn(),
      _customerColumn(),
      // Only a quotation has a valid date; an order is not an offer.
      if (widget.kind == SalesDocumentKind.quotation) _validUntilColumn(),
      _totalColumn(),
      if (withAction) _actionColumn(),
    ];
  }

  /// Number with its status under it.
  ///
  /// The badge rides in this column instead of a Status column of its own: a
  /// seventh and sixth column pushed the total and the View action off a
  /// 1100 px window, which is the defect this screen is being rebuilt for, and
  /// the narrow card already lays the two out exactly like this.
  DataPanelColumn<SalesDocumentRow> _numberColumn() {
    return DataPanelColumn<SalesDocumentRow>(
      label: switch (widget.kind) {
        SalesDocumentKind.quotation => 'Quotation',
        SalesDocumentKind.order => 'Order',
      },
      flex: 2,
      cell: (row) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.number,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          StatusBadge(label: row.statusLabel, tone: row.tone),
        ],
      ),
    );
  }

  /// The customer, with the document's own date underneath: who it is for is
  /// what the reader scans for, and the date is how two documents for the same
  /// customer are told apart.
  DataPanelColumn<SalesDocumentRow> _customerColumn() {
    return DataPanelColumn<SalesDocumentRow>(
      label: 'Customer',
      flex: 3,
      cell: (row) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(row.customer, maxLines: 2),
          const SizedBox(height: 2),
          _caption(switch (widget.kind) {
            SalesDocumentKind.quotation => 'Created ${formatDate(row.date)}',
            SalesDocumentKind.order => 'Order date ${formatDate(row.date)}',
          }),
        ],
      ),
    );
  }

  DataPanelColumn<SalesDocumentRow> _validUntilColumn() {
    return DataPanelColumn<SalesDocumentRow>(
      label: 'Valid until',
      flex: 2,
      cell: (row) => _text(formatDate(row.validUntil ?? row.date)),
    );
  }

  /// Two shares, not one: money is what the manager scans down, and a single
  /// share clipped a seven digit total beside columns holding one word.
  DataPanelColumn<SalesDocumentRow> _totalColumn() {
    return DataPanelColumn<SalesDocumentRow>(
      label: 'Total',
      numeric: true,
      flex: 2,
      cell: (row) => _text(formatPeso(row.total)),
    );
  }

  DataPanelColumn<SalesDocumentRow> _actionColumn() {
    return DataPanelColumn<SalesDocumentRow>(
      // Action is a button, not a name: one share, so Customer can take three.
      label: 'Action',
      flex: 1,
      cell: (row) => Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: row.onOpen,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(44, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('View'),
        ),
      ),
    );
  }

  Widget _text(String value, {int maxLines = 1}) {
    return Text(
      value,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
    );
  }

  Widget _caption(String value) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }
}
