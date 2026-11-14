// Phase 4 Task F1: DataPanel pages its own rows, 25 at a time.
//
// The pager is the panel's, not the page's: every screen that hands DataPanel a
// filtered list gets the same slice, the same words ("1 to 25 of 340") and the
// same two buttons, so no page grows its own half-pager. The count pill keeps
// meaning "rows after the filter", which is the number the pager counts to.

import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pager = ValueKey('DataPanel.pager');
  const previous = ValueKey('DataPanel.previous');
  const next = ValueKey('DataPanel.next');
  const pill = ValueKey('DataPanel.count');
  const table = ValueKey('DataPanel.table');
  const cards = ValueKey('DataPanel.cards');

  List<DataPanelColumn<_Row>> columns() => [
    DataPanelColumn<_Row>(
      label: 'Name',
      cell: (row) =>
          Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    DataPanelColumn<_Row>(
      label: 'Qty',
      numeric: true,
      cell: (row) => Text('${row.qty}'),
    ),
  ];

  List<_Row> rows(int count) =>
      List.generate(count, (index) => _Row('Row $index', index));

  Widget panel(
    List<_Row> data, {
    int pageSize = DataPanel.defaultPageSize,
    bool paginate = true,
    String? title,
    int? count,
  }) => DataPanel<_Row>(
    columns: columns(),
    rows: data,
    emptyMessage: 'No rows yet.',
    pageSize: pageSize,
    paginate: paginate,
    title: title,
    count: count,
  );

  /// Pumped inside a page scroll view: the panel has no height of its own and
  /// lays its rows out as a plain Column.
  Future<void> pumpUnbounded(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1440, 900);
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
    await tester.pumpAndSettle();
  }

  /// Pumped into a slot of its own (an `Expanded`), the way a real list page
  /// gives it one: the panel then scrolls its own rows.
  Future<void> pumpBounded(
    WidgetTester tester,
    Widget child, {
    Size? size,
  }) async {
    tester.view.physicalSize = size ?? const Size(1440, 900);
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

  /// Narrow enough that the panel draws cards instead of a table.
  Future<void> pumpCards(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(child: SizedBox(width: 700, child: child)),
          ),
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

  bool enabled(WidgetTester tester, Key key) =>
      tester.widget<IconButton>(find.byKey(key)).onPressed != null;

  /// The pager sits under the rows, so on a page scroll view it can start
  /// below the fold: bring it into view before tapping, as a reader would.
  Future<void> tapButton(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> tapNext(WidgetTester tester) => tapButton(tester, next);

  Future<void> tapPrevious(WidgetTester tester) => tapButton(tester, previous);

  // --------------------------------------------------------------- the slice

  testWidgets('26 rows become 25 on the first page and the rest on page 2', (
    tester,
  ) async {
    await pumpUnbounded(tester, panel(rows(26)));

    expect(find.byKey(pager), findsOneWidget);
    expect(find.text('1 to 25 of 26'), findsOneWidget);
    expect(builtRows().evaluate().length, 25);
    expect(find.text('Row 25'), findsNothing, reason: 'Row 25 waits on page 2');

    await tapNext(tester);

    expect(find.text('26 to 26 of 26'), findsOneWidget);
    expect(builtRows().evaluate().length, 1);
    expect(find.text('Row 25'), findsOneWidget);
    expect(find.text('Row 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the last page of 60 rows ends on a partial slice', (
    tester,
  ) async {
    await pumpUnbounded(tester, panel(rows(60)));

    await tapNext(tester);
    expect(find.text('26 to 50 of 60'), findsOneWidget);

    await tapNext(tester);
    expect(find.text('51 to 60 of 60'), findsOneWidget);
    expect(builtRows().evaluate().length, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Previous is off on the first page, Next is off on the last', (
    tester,
  ) async {
    await pumpUnbounded(tester, panel(rows(30)));

    expect(enabled(tester, previous), isFalse);
    expect(enabled(tester, next), isTrue);

    await tapNext(tester);

    expect(find.text('26 to 30 of 30'), findsOneWidget);
    expect(enabled(tester, previous), isTrue);
    expect(enabled(tester, next), isFalse);

    await tapPrevious(tester);

    expect(find.text('1 to 25 of 30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the buttons carry tooltips a pointer can find', (tester) async {
    await pumpUnbounded(tester, panel(rows(30)));

    expect(find.byTooltip('Previous page'), findsOneWidget);
    expect(find.byTooltip('Next page'), findsOneWidget);
  });

  // -------------------------------------------------------------- the words

  testWidgets('25 rows a page is the default', (tester) async {
    // Built without a pageSize, the way every real screen calls it.
    await pumpUnbounded(
      tester,
      DataPanel<_Row>(
        columns: columns(),
        rows: rows(26),
        emptyMessage: 'No rows yet.',
      ),
    );

    expect(DataPanel.defaultPageSize, 25);
    expect(find.text('1 to 25 of 26'), findsOneWidget);
  });

  testWidgets('the range counts in thousands, with no dash', (tester) async {
    await pumpUnbounded(tester, panel(rows(340)));

    expect(find.text('1 to 25 of 340'), findsOneWidget);
    expect(find.textContaining('\u2013'), findsNothing);
    expect(find.textContaining('\u2014'), findsNothing);

    expect(formatCount(340), '340');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the count pill still means rows after the filter, not the page',
    (tester) async {
      await pumpUnbounded(tester, panel(rows(60), title: 'Stock', count: 60));

      final pillText = tester
          .widget<Text>(
            find.descendant(of: find.byKey(pill), matching: find.byType(Text)),
          )
          .data;
      expect(pillText, '60', reason: 'the pill counts the filtered list');
      expect(find.text('1 to 25 of 60'), findsOneWidget);
    },
  );

  // ------------------------------------------------------------- the hiding

  for (final count in [0, 1, 25]) {
    testWidgets('$count rows get no pager at all', (tester) async {
      await pumpUnbounded(tester, panel(rows(count)));

      expect(find.byKey(pager), findsNothing);
      expect(find.byKey(next), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('paginate: false shows every row and no pager', (tester) async {
    await pumpUnbounded(tester, panel(rows(60), paginate: false));

    expect(find.byKey(pager), findsNothing);
    expect(builtRows().evaluate().length, 60);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pageSize sets the slice and the page count', (tester) async {
    await pumpUnbounded(tester, panel(rows(45), pageSize: 10));

    expect(find.text('1 to 10 of 45'), findsOneWidget);
    expect(builtRows().evaluate().length, 10);

    await tapNext(tester);
    expect(find.text('11 to 20 of 45'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // -------------------------------------------------------------- the reset

  testWidgets('page 1 again when the filter changes the rows', (tester) async {
    final all = rows(60);
    await pumpUnbounded(tester, panel(all));
    await tapNext(tester);
    expect(find.text('26 to 50 of 60'), findsOneWidget);

    // A filter narrows the list: the reader is on page 2 of a list that no
    // longer has 60 rows, so the panel must fall back to its first page.
    await pumpUnbounded(tester, panel(all.sublist(0, 30)));

    expect(find.text('1 to 25 of 30'), findsOneWidget);
    expect(find.byKey(pager), findsOneWidget);
  });

  testWidgets('page 1 again when the rows are replaced by another list', (
    tester,
  ) async {
    await pumpUnbounded(tester, panel(rows(60)));
    await tapNext(tester);

    await pumpUnbounded(tester, panel(rows(80)));

    expect(find.text('1 to 25 of 80'), findsOneWidget);
  });

  testWidgets('a rebuild with the same rows keeps the reader on their page', (
    tester,
  ) async {
    final same = rows(60);
    await pumpUnbounded(tester, panel(same));
    await tapNext(tester);
    expect(find.text('26 to 50 of 60'), findsOneWidget);

    // The page rebuilds for an unrelated reason (a counter ticks); the same
    // 60 rows must not throw the reader back to page 1.
    await pumpUnbounded(tester, panel(List<_Row>.of(same)));

    expect(find.text('26 to 50 of 60'), findsOneWidget);
  });

  // ----------------------------------------------------------- the keyboard

  testWidgets('Tab reaches Next and Enter turns the page', (tester) async {
    await pumpUnbounded(tester, panel(rows(60)));

    // Previous is disabled on page 1, so it is not a focus stop: the first Tab
    // lands on Next.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('26 to 50 of 60'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ------------------------------------------------------------ the reader

  testWidgets('a screen reader hears which page it is on', (tester) async {
    final semantics = tester.ensureSemantics();

    await pumpUnbounded(tester, panel(rows(340)));

    expect(find.bySemanticsLabel('Page 1 of 14'), findsOneWidget);

    await tapNext(tester);
    expect(find.bySemanticsLabel('Page 2 of 14'), findsOneWidget);
    expect(tester.takeException(), isNull);

    semantics.dispose();
  });

  // ------------------------------------------------------------- the layouts

  testWidgets('cards under 720 px page too', (tester) async {
    await pumpCards(tester, panel(rows(30)));

    expect(find.byKey(cards), findsOneWidget);
    expect(find.byKey(table), findsNothing);
    expect(find.text('1 to 25 of 30'), findsOneWidget);
    expect(builtCards().evaluate().length, 25);

    await tapNext(tester);

    expect(find.text('26 to 30 of 30'), findsOneWidget);
    expect(builtCards().evaluate().length, 5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bounded slot pages: 2,000 rows cost one page of widgets', (
    tester,
  ) async {
    await pumpBounded(tester, panel(rows(2000)));

    expect(find.text('1 to 25 of 2,000'), findsOneWidget);
    expect(
      builtRows().evaluate().length,
      lessThan(100),
      reason: 'only the 25 rows of the current page are built',
    );

    await tapNext(tester);
    expect(find.text('26 to 50 of 2,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing the page starts the rows from the top again', (
    tester,
  ) async {
    await pumpBounded(tester, panel(rows(2000)), size: const Size(1440, 400));

    final scrollable = find
        .descendant(of: find.byKey(table), matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();

    await tapNext(tester);

    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      0,
      reason: 'a new page must be read from its first row',
    );
    expect(tester.takeException(), isNull);
  });
}

class _Row {
  const _Row(this.name, this.qty);

  final String name;
  final int qty;
}
