import 'dart:math' as math;

import 'package:client/core/constants/app_colors.dart';
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
  /// pushing the row wider.
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
/// The empty and error states never take the slot: in a bounded slot they sit at
/// the top of it at their own height, so a failed read is one banner and an
/// empty list is one small card, not a full-height pink block or a white void.
class DataPanel<T> extends StatelessWidget {
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
  });

  /// Below this content width the table becomes cards.
  static const double cardBreakpoint = 720;

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

  @override
  Widget build(BuildContext context) {
    // Precedence is loading, then error, then empty, then data: a retry holds
    // the previous failure while the next attempt runs, and reporting "no
    // records" for a failed request is a lie the user cannot see through.
    if (isLoading) {
      return const AppPanel(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final failure = error;
    if (failure != null) {
      // Top aligned in a loose box: the slot (an `Expanded`) hands down a tight
      // height, and a banner stretched over it read as a full-page error. Align
      // loosens the constraint, so the banner keeps its own one-line height and
      // still spans the width.
      return Align(
        alignment: Alignment.topCenter,
        child: ErrorBanner(message: failure, onRetry: onRetry),
      );
    }

    if (rows.isEmpty) {
      // Same reason as the failure above: the card hugs its message at the top
      // of the slot instead of a white void with the icon halfway down it.
      return Align(
        alignment: Alignment.topCenter,
        child: AppPanel(
          child: EmptyState(icon: Icons.inbox_outlined, message: emptyMessage),
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
              child: contentWidth >= cardBreakpoint
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
        itemCount: rows.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _card(context, index),
      );
    }

    return Column(
      key: const ValueKey('DataPanel.cards'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < rows.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          _card(context, index),
        ],
      ],
    );
  }

  Widget _card(BuildContext context, int index) {
    final row = rows[index];
    final title = columns.first;
    final rest = columns.skip(1);

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
                  width: _cardLabelWidth,
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

    final key = rowKey?.call(row) ?? ValueKey('DataPanel.card.$index');
    if (onRowTap == null) return KeyedSubtree(key: key, child: content);
    return InkWell(key: key, onTap: () => onRowTap!(row), child: content);
  }

  // --------------------------------------------------------------- table

  Widget _table(BuildContext context, double contentWidth, bool scrolls) {
    // The row can only be narrower than this if every column is squeezed below
    // its minimum, and then the table scrolls sideways rather than wrapping.
    final minimumWidth = columns.fold<double>(
      0,
      (sum, column) =>
          sum + (column.numeric ? _minNumericWidth : _minTextWidth),
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
                itemCount: rows.length,
                itemBuilder: (context, index) => _bodyRow(context, index),
              ),
            )
          else
            for (var index = 0; index < rows.length; index++)
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
      child: Row(children: columns.map(_headerCell).toList()),
    );
  }

  Widget _headerCell(DataPanelColumn<T> column) {
    return Expanded(
      flex: _flex(column),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _columnGutter),
        child: Align(
          alignment: column.numeric
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Text(
            column.label,
            maxLines: 1,
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
    final row = rows[index];
    final content = Container(
      constraints: const BoxConstraints(minHeight: _rowMinHeight),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: index == rows.length - 1
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
      child: Row(
        children: [
          for (final column in columns)
            Expanded(
              flex: _flex(column),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _columnGutter),
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

    final key = rowKey?.call(row) ?? ValueKey('DataPanel.row.$index');
    if (onRowTap == null) return KeyedSubtree(key: key, child: content);
    return InkWell(key: key, onTap: () => onRowTap!(row), child: content);
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
