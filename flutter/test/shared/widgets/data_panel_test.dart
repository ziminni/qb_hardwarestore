import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// DataPanel is the one place a list of records is rendered: a table when its
/// own content is wide enough, a stack of cards when it is not, with the empty,
/// loading and error states built in.
///
/// The narrow case is pumped inside a 700 px box on purpose: it proves the
/// choice follows the PANEL's content width, not the window width.
void main() {
  const table = ValueKey('DataPanel.table');
  const header = ValueKey('DataPanel.header');
  const cards = ValueKey('DataPanel.cards');

  const row0 = ValueKey('DataPanel.row.0');
  const row1 = ValueKey('DataPanel.row.1');
  const card0 = ValueKey('DataPanel.card.0');
  const card1 = ValueKey('DataPanel.card.1');

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Widget child, {
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  const rows = <_StockRow>[
    _StockRow('Portland Cement 40 kg', 'bag', 120, 285.00, 'In stock'),
    _StockRow('Deformed Steel Bar 10 mm', 'length', 64, 9000.00, 'Low stock'),
    _StockRow('Marine Plywood 3/4 in', 'sheet', 18, 1480.50, 'In stock'),
  ];

  List<DataPanelColumn<_StockRow>> columns() => [
    DataPanelColumn<_StockRow>(
      label: 'Product',
      cell: (row) =>
          Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    DataPanelColumn<_StockRow>(label: 'Unit', cell: (row) => Text(row.unit)),
    DataPanelColumn<_StockRow>(
      label: 'Qty',
      numeric: true,
      cell: (row) => Text(formatCount(row.qty)),
    ),
    DataPanelColumn<_StockRow>(
      label: 'Price',
      numeric: true,
      cell: (row) => Text(formatPeso(row.price)),
    ),
    DataPanelColumn<_StockRow>(
      label: 'Status',
      cell: (row) => StatusBadge(label: row.status, tone: StatusTone.success),
    ),
  ];

  Widget panel({
    List<_StockRow> data = rows,
    bool isLoading = false,
    String? error,
    VoidCallback? onRetry,
    ValueChanged<_StockRow>? onRowTap,
    List<DataPanelColumn<_StockRow>>? cols,
  }) => DataPanel<_StockRow>(
    columns: cols ?? columns(),
    rows: data,
    emptyMessage: 'No stock records yet.',
    isLoading: isLoading,
    error: error,
    onRetry: onRetry,
    onRowTap: onRowTap,
  );

  // --------------------------------------------------------------- wide table

  testWidgets('at 1440 px renders a table whose header is a row of labels', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1440, 900), panel());

    expect(find.byKey(table), findsOneWidget);
    expect(find.byKey(cards), findsNothing);

    final headerRow = find.byKey(header);
    expect(headerRow, findsOneWidget);
    for (final label in ['Product', 'Unit', 'Qty', 'Price', 'Status']) {
      expect(
        find.descendant(of: headerRow, matching: find.text(label)),
        findsOneWidget,
        reason: 'header label $label',
      );
    }
    expect(find.text('Portland Cement 40 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('at 1440 px the table fills the width it is given', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1440, 900), panel());

    final tableWidth = tester.getSize(find.byKey(table)).width;
    expect(
      tableWidth,
      greaterThanOrEqualTo(1440 * 0.9),
      reason: 'a 1440 px screen must not get a small centred table',
    );
  });

  testWidgets('table rows are at least 44 px tall', (tester) async {
    await pumpAt(tester, const Size(1440, 900), panel());

    expect(tester.getSize(find.byKey(row0)).height, greaterThanOrEqualTo(44));
  });

  // ------------------------------------------------------------ narrow cards

  testWidgets('at 760 px inside a panel under 720 px wide renders cards', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const Size(760, 900),
      Center(child: SizedBox(width: 700, child: panel())),
    );

    expect(find.byKey(cards), findsOneWidget);
    expect(find.byKey(table), findsNothing);
    expect(
      find.byKey(header),
      findsNothing,
      reason: 'cards carry their own labels, not a header row',
    );

    // The primary (first) column is the card's title; the rest are label/value
    // lines on the same card.
    final card = find.byKey(card0);
    expect(
      find.descendant(of: card, matching: find.text('Portland Cement 40 kg')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('Unit')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('bag')),
      findsOneWidget,
    );
    expect(find.byKey(card1), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ------------------------------------------------------------- money column

  testWidgets('money cells are right aligned with tabular figures in a table', (
    tester,
  ) async {
    await pumpAt(tester, const Size(1440, 900), panel());

    final money = find.text('₱9,000.00');
    expect(money, findsOneWidget);

    final align = tester.widget<Align>(
      find.ancestor(of: money, matching: find.byType(Align)).first,
    );
    expect(align.alignment, Alignment.centerRight);

    final style = tester
        .widget<DefaultTextStyle>(
          find
              .ancestor(of: money, matching: find.byType(DefaultTextStyle))
              .first,
        )
        .style;
    expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  testWidgets('money cells are right aligned in a card too', (tester) async {
    await pumpAt(
      tester,
      const Size(760, 900),
      Center(child: SizedBox(width: 700, child: panel())),
    );

    final money = find.text('₱9,000.00');
    expect(money, findsOneWidget);
    final align = tester.widget<Align>(
      find.ancestor(of: money, matching: find.byType(Align)).first,
    );
    expect(align.alignment, Alignment.centerRight);
  });

  // ----------------------------------------------------------------- row tap

  testWidgets('tapping a table row reports that row', (tester) async {
    final taps = <_StockRow>[];
    await pumpAt(tester, const Size(1440, 900), panel(onRowTap: taps.add));

    await tester.tap(find.byKey(row1));
    await tester.pumpAndSettle();

    expect(taps, hasLength(1));
    expect(taps.single.name, 'Deformed Steel Bar 10 mm');
  });

  testWidgets('tapping a card reports that row', (tester) async {
    final taps = <_StockRow>[];
    await pumpAt(
      tester,
      const Size(760, 900),
      Center(
        child: SizedBox(width: 700, child: panel(onRowTap: taps.add)),
      ),
    );

    await tester.tap(find.byKey(card1));
    await tester.pumpAndSettle();

    expect(taps, hasLength(1));
    expect(taps.single.name, 'Deformed Steel Bar 10 mm');
  });

  // ------------------------------------------------------- built in states

  for (final size in const [Size(1440, 900), Size(760, 900)]) {
    final width = size.width.toInt();

    testWidgets('shows the caller empty message when there are no rows '
        'at $width px', (tester) async {
      await pumpAt(tester, size, panel(data: const []));

      expect(find.text('No stock records yet.'), findsOneWidget);
      expect(find.byKey(table), findsNothing);
      expect(find.byKey(cards), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows a spinner while loading', (tester) async {
    await pumpAt(
      tester,
      const Size(1440, 900),
      panel(data: const [], isLoading: true),
      settle: false,
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No stock records yet.'), findsNothing);
  });

  testWidgets('shows the error banner and retries', (tester) async {
    var retries = 0;
    await pumpAt(
      tester,
      const Size(1440, 900),
      panel(
        data: const [],
        error: 'Stock could not be loaded.',
        onRetry: () => retries++,
      ),
    );

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('Stock could not be loaded.'), findsOneWidget);
    expect(find.text('No stock records yet.'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(retries, 1);
  });

  // ------------------------------------------------------------------ long text

  for (final size in const [Size(1440, 900), Size(760, 900)]) {
    final width = size.width.toInt();

    testWidgets(
      'a 120 character name never overflows at ${size.width.toInt()} px',
      (tester) async {
        final longName = 'Reinforced concrete hollow block '.padRight(120, 'x');
        expect(longName.length, 120);

        // Full width at 1440 (the table branch) and 660 px at 760 (the card
        // branch), so both layouts are made to hold the long name.
        final contentWidth = width >= 1440 ? double.infinity : 660.0;

        await pumpAt(
          tester,
          size,
          Center(
            child: SizedBox(
              width: contentWidth,
              child: panel(
                data: [_StockRow(longName, 'piece', 4, 1234567.89, 'In stock')],
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.textContaining('Reinforced concrete'), findsOneWidget);
      },
    );
  }

  // ---------------------------------------------------- long lists, bounded

  /// A panel that owns its height, the way a page slot does: `Expanded` around
  /// it. Page scrolling is not involved, so the panel must scroll its own rows.
  Future<void> pumpBounded(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Column(children: [Expanded(child: child)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder builtRows() => find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('DataPanel.row.');
  });

  Finder builtCards() => find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('DataPanel.card.');
  });

  List<_StockRow> manyRows(int count) => List.generate(
    count,
    (index) =>
        _StockRow('Row $index', 'bag', index, index.toDouble(), 'In stock'),
  );

  /// Scrolls the panel's own list to its end. Jumping beats dragging here:
  /// 2,000 rows are tens of thousands of pixels long.
  Future<void> scrollToEnd(WidgetTester tester, Finder within) async {
    final scrollable = find
        .descendant(of: within, matching: find.byType(Scrollable))
        .first;
    for (var attempt = 0; attempt < 5; attempt++) {
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('2,000 rows in a bounded slot build only the visible ones', (
    tester,
  ) async {
    await pumpBounded(
      tester,
      const Size(1440, 600),
      panel(data: manyRows(2000)),
    );

    expect(find.byKey(table), findsOneWidget);
    expect(
      builtRows().evaluate().length,
      lessThan(100),
      reason: 'a 600 px slot must not build 2,000 row subtrees',
    );
    // The header is not part of the scrolling list.
    expect(find.byKey(header), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the last of 2,000 rows is reachable and reports itself', (
    tester,
  ) async {
    final taps = <_StockRow>[];
    await pumpBounded(
      tester,
      const Size(1440, 600),
      panel(data: manyRows(2000), onRowTap: taps.add),
    );

    await scrollToEnd(tester, find.byKey(table));

    expect(find.text('Row 1999'), findsOneWidget);
    await tester.tap(find.text('Row 1999'));
    await tester.pumpAndSettle();
    expect(taps, hasLength(1));
    expect(taps.single.name, 'Row 1999');
  });

  testWidgets('2,000 cards in a bounded slot build only the visible ones', (
    tester,
  ) async {
    await pumpBounded(
      tester,
      const Size(760, 600),
      Center(
        child: SizedBox(width: 700, child: panel(data: manyRows(2000))),
      ),
    );

    expect(find.byKey(cards), findsOneWidget);
    expect(
      builtCards().evaluate().length,
      lessThan(100),
      reason: 'a 600 px slot must not build 2,000 card subtrees',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unbounded slot still builds every row at once', (
    tester,
  ) async {
    // Inside a page scroll view the panel has no height of its own, so it must
    // keep the plain Column: a ListView there would nest scroll views.
    await pumpAt(
      tester,
      const Size(1440, 900),
      panel(data: manyRows(50)),
      settle: false,
    );

    expect(builtRows().evaluate().length, 50);
    expect(tester.takeException(), isNull);
  });
}

class _StockRow {
  const _StockRow(this.name, this.unit, this.qty, this.price, this.status);

  final String name;
  final String unit;
  final int qty;
  final double price;
  final String status;
}
