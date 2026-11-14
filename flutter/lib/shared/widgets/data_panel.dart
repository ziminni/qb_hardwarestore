import 'dart:math' as math;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';

/// One column of a [DataPanel]: its heading and how to render a row's cell.
class DataPanelColumn<T> {
  const DataPanelColumn({
    required this.label,
    required this.cell,
    this.numeric = false,
    this.flex = 1,
  }) : assert(flex >= 1, 'a column cannot take less than one share');

  final String label;

  /// Builds the cell for one row. A `Text` with `overflow: ellipsis` and
  /// `maxLines: 1` is the usual shape, so long names shorten instead of
  /// pushing the row wider. Give a value that must never be cut in half - a
  /// date and its time, "Not counted yet" - `maxLines: 2`: at a raised text
  /// scale a narrow column then wraps it rather than losing the end of it.
  final Widget Function(T row) cell;

  /// Money and counts: right aligned with tabular digits, so a column of
  /// amounts can be read down the decimal point.
  final bool numeric;

  /// How many shares of the table's width this column takes, relative to its
  /// siblings. Must be at least 1.
  final int flex;
}

/// A list of records as a table when it is wide enough, a stack of cards when
/// it is not, with the empty, loading and error states built in.
///
/// The layout follows the panel's OWN content width, not the window width: a
/// panel sitting in a narrow column of a wide screen still gets cards.
///
/// The first column is the card's title on a narrow panel; the remaining
/// columns become label and value lines.
///
/// Give the primary text column (a product name) a larger [DataPanelColumn.flex]
/// such as 3 and leave status or action columns at 1, so long names get room
/// instead of ellipsizing into a column as wide as the badge next to it.
///
/// Long lists belong in a slot with a bounded height, an `Expanded` inside a
/// `Column` or the body of a `Scaffold`. There the panel scrolls its own rows
/// and builds only the visible ones, so a 2,000 row requisition list costs a
/// screenful of widgets, not 2,000. Inside a page scroll view the panel has no
/// height of its own and lays every row out at once: that is the right choice
/// for a short list, and a nested scroll view for a long one.
///
/// More rows than [pageSize] are paged, not scrolled into: the panel lays out
/// one page at a time and puts "1 to 25 of 340" with Previous and Next under
/// it. Paging is client side, on the rows the caller already filtered, so a list
/// of 25 or fewer looks exactly as it did before the pager existed. A caller
/// that pages on the server passes [paginate] false.
///
/// The empty and error states never take the slot: in a bounded slot they sit at
/// the top of it at their own height, so a failed read is one banner and an
/// empty list is one small card, not a full-height pink block or a white void.
class DataPanel<T> extends StatefulWidget {
  const DataPanel({
    super.key,
    required this.columns,
    required this.rows,
    required this.emptyMessage,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.onRowTap,
    this.rowKey,
    this.controller,
    this.title,
    this.count,
    this.pageSize = defaultPageSize,
    this.paginate = true,
  }) : assert(pageSize >= 1, 'a page holds at least one row');

  /// Below this content width the table becomes cards.
  static const double cardBreakpoint = 720;

  /// Rows per page when [paginate] is on.
  static const int defaultPageSize = 25;

  static const double _minTextWidth = 140;
  static const double _minNumericWidth = 110;
  static const double _rowMinHeight = 44;

  /// Keeps a right-aligned money column from touching the next column.
  static const double _columnGutter = 8;

  /// Width of the label column on a card, so a value sits next to its label
  /// instead of halfway across the card.
  static const double _cardLabelWidth = 110;

  final List<DataPanelColumn<T>> columns;
  final List<T> rows;

  /// Shown when [rows] is empty. The caller words it, because "nothing matches
  /// this search" and "nothing exists yet" are different facts.
  final String emptyMessage;

  final bool isLoading;
  final String? error;

  /// Retry action for [error]. Without it the banner has no button.
  final VoidCallback? onRetry;

  /// Makes each row tappable (to open a detail sheet, usually).
  final ValueChanged<T>? onRowTap;

  /// Stable key per row, when the caller has an id to spare.
  final Key Function(T row)? rowKey;

  /// The rows' vertical scroll position, when the page wants a say in it.
  ///
  /// A page whose own header fills the window (`a 760 x 900 staff list spends a
  /// third of it above the first card`) can hand a wheel that landed on the
  /// header straight to the rows through this. Null lets the panel own one.
  final ScrollController? controller;

  /// The list's own title, drawn above the panel: `DataPanel` brings the card
  /// but no heading, and a second panel around it would draw a second border.
  ///
  /// Null and [count] null is the panel exactly as it was before either
  /// existed, which is why the callers that do not want a heading never change.
  final String? title;

  /// Number of rows after filtering, read out in words ("12 rows shown"). Pass
  /// `rows.length`, not the server's unfiltered total.
  ///
  /// Paging happens after this: the pill counts every row that matches the
  /// filter, while the pager under the rows shows one page of them. It never
  /// means "rows on this page".
  final int? count;

  /// Rows per page. A list longer than this gets a pager under the rows.
  final int pageSize;

  /// False renders every row in one list with no pager, for a caller that
  /// already slices its own rows.
  final bool paginate;

  @override
  State<DataPanel<T>> createState() => _DataPanelState<T>();
}

class _DataPanelState<T> extends State<DataPanel<T>> {
  int _page = 1;

  /// The panel's own scroll position, made only when the caller handed none.
  ScrollController? _ownController;

  int get _pageCount {
    final total = widget.rows.length;
    if (total == 0) return 1;
    return (total + widget.pageSize - 1) ~/ widget.pageSize;
  }

  /// Paging is off for a list that fits on one page: a 12 row list gets the
  /// panel it always had, not a disabled pair of buttons.
  bool get _paged => widget.paginate && _pageCount > 1;

  /// Where the current page starts in [DataPanel.rows], so a default row key
  /// names the record, not the slot: row 26 of page 2 is keyed 26, as it is on
  /// page 1 of a 200 row list.
  int get _pageOffset => _paged ? (_page - 1) * widget.pageSize : 0;

  /// The rows this panel lays out: the current page when paging is on. Every
  /// layout below reads this, so the table, the cards and the "last row" border
  /// all agree on where the slice ends.
  List<T> get _rows {
    if (!_paged) return widget.rows;
    final start = (_page - 1) * widget.pageSize;
    final end = math.min(start + widget.pageSize, widget.rows.length);
    return widget.rows.sublist(start, end);
  }

  ScrollController? get _rowsController =>
      widget.controller ?? (_ownController ??= ScrollController());

  @override
  void didUpdateWidget(DataPanel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another list is another list: a filter leaving 30 rows would strand the
    // reader on a page that no longer exists, halfway through rows they never
    // asked for.
    if (widget.pageSize != oldWidget.pageSize ||
        !_sameRows(oldWidget.rows, widget.rows)) {
      _page = 1;
    } else if (_page > _pageCount) {
      _page = _pageCount;
    }
  }

  /// Same list, row for row. A page that rebuilds and rebuilds a list of the
  /// same records keeps the reader where they were; a filtered one does not.
  bool _sameRows(List<T> before, List<T> after) {
    if (identical(before, after)) return true;
    if (before.length != after.length) return false;
    for (var index = 0; index < before.length; index++) {
      if (!identical(before[index], after[index])) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    setState(() => _page = page);
    // A new page is read from its first row, not from where the last one was
    // scrolled to.
    final controller = _ownController ?? widget.controller;
    if (controller != null && controller.hasClients) controller.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final heading = _heading();
    final panel = _panel(context);
    final footer = _footer();
    if (heading == null && footer == null) return panel;

    // A page that gave the panel a slot of its own (an `Expanded`) hands down a
    // bounded height: the heading takes its line, the pager its strip, and the
    // panel keeps the rest, so the rows still scroll inside the panel. A page
    // that scrolls itself hands down no bound; there the three stack at their
    // own heights.
    return LayoutBuilder(
      builder: (context, slot) {
        final bounded = slot.maxHeight.isFinite;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            ?heading,
            if (bounded) Expanded(child: panel) else panel,
            ?footer,
          ],
        );
      },
    );
  }

  /// The strip under the rows: which slice is on screen and the two buttons
  /// that walk it. Null when the list fits on one page.
  Widget? _footer() {
    if (!_paged) return null;

    final pages = _pageCount;
    final start = (_page - 1) * widget.pageSize;
    final end = math.min(start + widget.pageSize, widget.rows.length);

    return Padding(
      key: const ValueKey('DataPanel.pager'),
      padding: const EdgeInsets.only(top: AppSpacing.md),
      // A wrap, not a row: at a raised text scale on a narrow card the range
      // and the buttons take a line each instead of overflowing.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.sm,
        children: [
          Text(
            '${formatCount(start + 1)} to ${formatCount(end)} '
            'of ${formatCount(widget.rows.length)}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const ValueKey('DataPanel.previous'),
                tooltip: 'Previous page',
                // Null disables the button and takes it out of the tab order,
                // which is what the end of the list should feel like.
                onPressed: _page > 1 ? () => _goTo(_page - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Semantics(
                label: 'Page $_page of $pages',
                child: ExcludeSemantics(
                  child: Text(
                    '$_page of $pages',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('DataPanel.next'),
                tooltip: 'Next page',
                onPressed: _page < pages ? () => _goTo(_page + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The title and count pill, or null when the caller wants neither.
  Widget? _heading() {
    if (widget.title == null && widget.count == null) return null;
    final label = widget.title;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: label == null
                ? const SizedBox.shrink()
                : Semantics(
                    header: true,
                    // Cinzel at 18 px: a list heading is a heading.
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.cinzelFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
          ),
          if (widget.count case final count?) _CountPill(count),
        ],
      ),
    );
  }

  Widget _panel(BuildContext context) {
    // Precedence is loading, then error, then empty, then data: a retry holds
    // the previous failure while the next attempt runs, and reporting "no
    // records" for a failed request is a lie the user cannot see through.
    if (widget.isLoading) {
      return const AppPanel(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final failure = widget.error;
    if (failure != null) {
      // Top aligned in a loose box: the slot (an `Expanded`) hands down a tight
      // height, and a banner stretched over it read as a full-page error. Align
      // loosens the constraint, so the banner keeps its own one-line height and
      // still spans the width.
      return Align(
        alignment: Alignment.topCenter,
        child: ErrorBanner(message: failure, onRetry: widget.onRetry),
      );
    }

    if (widget.rows.isEmpty) {
      // Same reason as the failure above: the card hugs its message at the top
      // of the slot instead of a white void with the icon halfway down it.
      return Align(
        alignment: Alignment.topCenter,
        child: AppPanel(
          child: EmptyState(
            icon: Icons.inbox_outlined,
            message: widget.emptyMessage,
          ),
        ),
      );
    }

    // The bound has to be read here, outside the panel: AppPanel's own Column
    // hands a plain child an unbounded height, and a LayoutBuilder inside the
    // panel would break equal-height layouts that ask it for intrinsics.
    return LayoutBuilder(
      builder: (context, slot) {
        final contentWidth = math.max(0.0, slot.maxWidth - AppPanel.chrome);
        // A finite height means the page gave the panel a slot of its own (an
        // Expanded), so it scrolls its own rows and builds only what is
        // visible. Unbounded means the page scrolls: a ListView here would nest
        // two scroll views.
        final scrolls = slot.maxHeight.isFinite;
        final bodyHeight = scrolls
            ? math.max(0.0, slot.maxHeight - AppPanel.chrome)
            : null;

        return AppPanel(
          child: SizedBox(
            height: bodyHeight,
            child: Material(
              type: MaterialType.transparency,
              child: contentWidth >= DataPanel.cardBreakpoint
                  ? _table(context, contentWidth, scrolls)
                  : _cards(context, contentWidth, scrolls),
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------------- cards

  /// Under 720 px of content a table would either clip or scroll sideways on
  /// every row, so each record becomes a card: the first column as its title.
  Widget _cards(BuildContext context, double contentWidth, bool scrolls) {
    if (scrolls) {
      return ListView.separated(
        key: const ValueKey('DataPanel.cards'),
        controller: _rowsController,
        itemCount: _rows.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _card(context, index),
      );
    }

    return Column(
      key: const ValueKey('DataPanel.cards'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < _rows.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _card(context, index),
        ],
      ],
    );
  }

  Widget _card(BuildContext context, int index) {
    final row = _rows[index];
    final title = widget.columns.first;
    final rest = widget.columns.skip(1);

    final content = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DefaultTextStyle.merge(
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: title.cell(row),
            ),
          ),
          for (final column in rest) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: DataPanel._cardLabelWidth,
                  child: Text(
                    column.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: column.numeric
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: _cell(column, row),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    final key =
        widget.rowKey?.call(row) ??
        ValueKey('DataPanel.card.${_pageOffset + index}');
    if (widget.onRowTap == null) return KeyedSubtree(key: key, child: content);
    return InkWell(
      key: key,
      onTap: () => widget.onRowTap!(row),
      child: content,
    );
  }

  // --------------------------------------------------------------- table

  Widget _table(BuildContext context, double contentWidth, bool scrolls) {
    // The row can only be narrower than this if every column is squeezed below
    // its minimum, and then the table scrolls sideways rather than wrapping.
    final minimumWidth = widget.columns.fold<double>(
      0,
      (sum, column) =>
          sum +
          (column.numeric
              ? DataPanel._minNumericWidth
              : DataPanel._minTextWidth),
    );
    final width = math.max(minimumWidth, contentWidth);

    final table = SizedBox(
      key: const ValueKey('DataPanel.table'),
      width: width,
      child: Column(
        mainAxisSize: scrolls ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The header stays above the scroll, so it does not slide away from
          // the columns it labels.
          _headerRow(),
          if (scrolls)
            Expanded(
              child: ListView.builder(
                controller: _rowsController,
                itemCount: _rows.length,
                itemBuilder: (context, index) => _bodyRow(context, index),
              ),
            )
          else
            for (var index = 0; index < _rows.length; index++)
              _bodyRow(context, index),
        ],
      ),
    );

    if (minimumWidth <= contentWidth) return table;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: table,
    );
  }

  Widget _headerRow() {
    return Container(
      key: const ValueKey('DataPanel.header'),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        // The tinted header band: it separates the labels from the rows
        // without another hairline doing the same job.
        color: AppColors.tableHeader,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: widget.columns.map(_headerCell).toList()),
    );
  }

  Widget _headerCell(DataPanelColumn<T> column) {
    return Expanded(
      flex: _flex(column),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DataPanel._columnGutter,
        ),
        child: Align(
          alignment: column.numeric
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Text(
            column.label,
            // Two lines, not one: "Reorder level" and "Closing count" are one
            // word too wide for their column once the text scale goes up, and a
            // heading cut to "Reorder le..." names nothing. A label longer than
            // that still ends in an ellipsis.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bodyRow(BuildContext context, int index) {
    final row = _rows[index];
    final content = Container(
      constraints: const BoxConstraints(minHeight: DataPanel._rowMinHeight),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: index == _rows.length - 1
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
      child: Row(
        children: [
          for (final column in widget.columns)
            Expanded(
              flex: _flex(column),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DataPanel._columnGutter,
                ),
                child: Align(
                  alignment: column.numeric
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: _cell(column, row),
                ),
              ),
            ),
        ],
      ),
    );

    final key =
        widget.rowKey?.call(row) ??
        ValueKey('DataPanel.row.${_pageOffset + index}');
    if (widget.onRowTap == null) return KeyedSubtree(key: key, child: content);
    return InkWell(
      key: key,
      onTap: () => widget.onRowTap!(row),
      child: content,
    );
  }

  Widget _cell(DataPanelColumn<T> column, T row) {
    final child = column.cell(row);
    if (!column.numeric) return child;
    return DefaultTextStyle.merge(
      style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      child: child,
    );
  }

  /// Shares of the row's width: the caller's [DataPanelColumn.flex], scaled so
  /// a money column never takes as much room as a name column. The default
  /// flex of 1 therefore splits the row exactly as it did before flex existed.
  int _flex(DataPanelColumn<T> column) =>
      column.flex * (column.numeric ? 2 : 3);
}

/// How many records the list holds, beside its title.
///
/// The screen reader hears words ("12 rows shown"), not a bare number floating
/// after a heading: a button or a field that reads "12" says nothing about what
/// the twelve are.
class _CountPill extends StatelessWidget {
  const _CountPill(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final shown = formatCount(count);

    return Semantics(
      label: '$shown ${count == 1 ? 'row' : 'rows'} shown',
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('DataPanel.count'),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: AppColors.selected,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Text(
            shown,
            style: const TextStyle(
              fontFamily: AppTextStyles.outfitFont,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              // Gold as ink: the brand gold is a fill colour and is under
              // 4.5:1 as 12 px text.
              color: AppColors.brandGoldText,
            ),
          ),
        ),
      ),
    );
  }
}
