// Task 6 (phase 1d): the shared dialog family, the shared section heading and
// the DataPanel title/count pill.
//
// HCI acceptance from the plan, checked here rather than by eye:
//   - Tab order runs header -> body fields -> footer actions, Esc closes, and
//     focus goes back to the button that opened the dialog;
//   - FormStepHeader is Open Sans: Cinzel is only for 18 px and up;
//   - TotalBar prints its figure through formatPeso, in Cinzel at 18 px or more;
//   - the InfoBanner and the count pill stay at 4.5:1 for their text;
//   - nothing clips at 1.3x text in a 760 px window with the REAL fonts.
//
// The font loading is the harness from test/features/table_text_scale_test.dart:
// the test font is one em per character, roughly twice as wide as Open Sans, so
// a layout measured with it would pass a screen that the browser then clips.

import 'dart:io';
import 'dart:math' as math;

import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/section_heading.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast of two opaque colours, the same arithmetic the browser uses.
double contrastOf(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    ('OpenSans', ['OpenSans-Regular.ttf', 'OpenSans-Bold.ttf']),
    ('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

/// A page with one button that opens [dialog], so focus has somewhere to come
/// back to.
class _Host extends StatelessWidget {
  const _Host({required this.opener, required this.dialog});

  final FocusNode opener;
  final Widget dialog;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Focus(
          focusNode: opener,
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showDialog<void>(context: context, builder: (_) => dialog),
              child: const Text('New product'),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(_loadAppFonts);

  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
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
    await tester.pumpAndSettle();
  }

  group('AppDialog', () {
    /// Opens the dialog the way a page does and hands back the nodes the test
    /// can see focused.
    Future<Map<String, FocusNode>> open(WidgetTester tester) async {
      final opener = FocusNode(debugLabel: 'opener');
      final name = FocusNode(debugLabel: 'name field');
      final price = FocusNode(debugLabel: 'price field');
      final cancel = FocusNode(debugLabel: 'cancel');
      final save = FocusNode(debugLabel: 'save');
      for (final node in [opener, name, price, cancel, save]) {
        addTearDown(node.dispose);
      }

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: _Host(
            opener: opener,
            dialog: AppDialog(
              icon: Icons.inventory_2_outlined,
              title: 'Add product',
              subtitle: 'Step 1 of 3',
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    focusNode: name,
                    decoration: const InputDecoration(
                      labelText: 'Product name',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    focusNode: price,
                    decoration: const InputDecoration(labelText: 'Price'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  focusNode: cancel,
                  onPressed: () {},
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  focusNode: save,
                  onPressed: () {},
                  child: const Text('Save product'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      opener.requestFocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('New product'));
      await tester.pumpAndSettle();
      return {
        'opener': opener,
        'name': name,
        'price': price,
        'cancel': cancel,
        'save': save,
      };
    }

    testWidgets('Tab runs from the header down the fields, then the actions', (
      tester,
    ) async {
      final nodes = await open(tester);

      // Whatever is focused, name it: a node the test owns, or the header's
      // close button, which AppDialog owns.
      String focused() {
        for (final entry in nodes.entries) {
          if (entry.key == 'opener') continue;
          if (entry.value.hasPrimaryFocus) return entry.key;
        }
        final context = FocusManager.instance.primaryFocus?.context;
        if (context != null &&
            context.findAncestorWidgetOfExactType<IconButton>() != null) {
          return 'close';
        }
        return 'nothing';
      }

      final order = <String>[];
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        order.add(focused());
      }

      expect(order, ['close', 'name', 'price', 'cancel', 'save']);
    });

    testWidgets('Esc closes the dialog and focus returns to the opener', (
      tester,
    ) async {
      final nodes = await open(tester);
      expect(find.byType(AppDialog), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(AppDialog), findsNothing);
      expect(
        nodes['opener']!.hasPrimaryFocus,
        isTrue,
        reason: 'a keyboard user must land back on the button they pressed',
      );
    });

    testWidgets('the close button pops the dialog', (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(AppDialog), findsNothing);
    });
  });

  group('FormStepHeader', () {
    testWidgets('numbers the step and writes the title in Open Sans', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const Size(760, 900),
        const FormStepHeader(step: 2, title: 'How is this product sold?'),
      );

      expect(find.text('2'), findsOneWidget);
      final title = tester.widget<Text>(find.text('How is this product sold?'));
      expect(title.style?.fontFamily, 'OpenSans');
      expect(
        title.style!.fontSize!,
        lessThan(18),
        reason: 'Cinzel below 18 px is the one thing the look rules forbid',
      );
    });
  });

  group('TotalBar', () {
    testWidgets(
      'prints the money through formatPeso in Cinzel at 18 px or up',
      (tester) async {
        await pumpAt(
          tester,
          const Size(760, 900),
          const TotalBar(label: 'Total', amount: 1234.5),
        );

        final figure = tester.widget<Text>(find.text(formatPeso(1234.5)));
        expect(figure.style?.fontFamily, 'Cinzel');
        expect(figure.style!.fontSize!, greaterThanOrEqualTo(18));
        expect(find.text('TOTAL'), findsOneWidget);
      },
    );
  });

  group('InfoBanner', () {
    testWidgets('its text clears 4.5:1 on the tint it sits on', (tester) async {
      const message = 'Stock arrives through a purchase order, then Receiving.';
      await pumpAt(
        tester,
        const Size(760, 900),
        const InfoBanner(message: message),
      );

      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(InfoBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      final background = (box.decoration! as BoxDecoration).color!;
      final text = tester.widget<Text>(find.text(message));
      final ink = text.style!.color!;

      expect(contrastOf(ink, background), greaterThanOrEqualTo(4.5));
    });
  });

  group('SectionHeading', () {
    testWidgets('Cinzel only at 18 px or up, subtitle in Open Sans', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const Size(760, 900),
        SectionHeading(
          title: 'Recent transactions',
          subtitle: 'The last 7 days',
          actions: [
            TextButton(onPressed: () {}, child: const Text('View all')),
          ],
        ),
      );

      final title = tester.widget<Text>(find.text('Recent transactions'));
      expect(title.style?.fontFamily, 'Cinzel');
      expect(title.style!.fontSize!, greaterThanOrEqualTo(18));

      final subtitle = tester.widget<Text>(find.text('The last 7 days'));
      expect(subtitle.style?.fontFamily, 'OpenSans');

      expect(find.text('View all'), findsOneWidget);
    });
  });

  group('DataPanel title and count', () {
    /// Runs [body] with the semantics tree switched on. The handle is disposed
    /// inside the test body on purpose: a handle left to a tear-down is still
    /// open when the framework checks for leaks.
    Future<void> withSemantics(
      WidgetTester tester,
      Future<void> Function() body,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await body();
      } finally {
        handle.dispose();
      }
    }

    List<DataPanelColumn<String>> columns() => [
      DataPanelColumn<String>(label: 'Product', cell: (row) => Text(row)),
    ];

    testWidgets('title and pill, the pill read out in words', (tester) async {
      await withSemantics(tester, () async {
        await pumpAt(
          tester,
          const Size(1440, 900),
          DataPanel<String>(
            title: 'Recent transactions',
            count: 3,
            columns: columns(),
            rows: const ['Cement', 'Plywood', 'Paint'],
            emptyMessage: 'No transactions yet.',
          ),
        );

        final title = tester.widget<Text>(find.text('Recent transactions'));
        expect(title.style?.fontFamily, 'Cinzel');
        expect(title.style!.fontSize!, greaterThanOrEqualTo(18));

        final pill = find.byKey(const ValueKey('DataPanel.count'));
        expect(pill, findsOneWidget);
        expect(find.text('3'), findsOneWidget);
        expect(find.bySemanticsLabel('3 rows shown'), findsOneWidget);

        // The pill's text has to clear 4.5:1 too.
        final box = tester.widget<Container>(pill);
        final background = (box.decoration! as BoxDecoration).color!;
        final text = tester.widget<Text>(
          find.descendant(of: pill, matching: find.text('3')),
        );
        expect(
          contrastOf(text.style!.color!, background),
          greaterThanOrEqualTo(4.5),
        );
      });
    });

    testWidgets('one row reads as "1 row shown"', (tester) async {
      await withSemantics(tester, () async {
        await pumpAt(
          tester,
          const Size(1440, 900),
          DataPanel<String>(
            title: 'Recent transactions',
            count: 1,
            columns: columns(),
            rows: const ['Cement'],
            emptyMessage: 'No transactions yet.',
          ),
        );

        expect(find.bySemanticsLabel('1 row shown'), findsOneWidget);
      });
    });

    testWidgets('a panel with no title is exactly the panel it was', (
      tester,
    ) async {
      await withSemantics(tester, () async {
        await pumpAt(
          tester,
          const Size(1440, 900),
          DataPanel<String>(
            columns: columns(),
            rows: const ['Cement'],
            emptyMessage: 'No transactions yet.',
          ),
        );

        expect(find.byKey(const ValueKey('DataPanel.count')), findsNothing);
        expect(find.text('Recent transactions'), findsNothing);
      });
    });
  });

  group('at 1.3x text in a 760 px window', () {
    testWidgets('the dialog lays out without clipping', (tester) async {
      const scale = TextScaler.linear(1.3);
      tester.view.physicalSize = const Size(760, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final opener = FocusNode();
      addTearDown(opener.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scale),
            child: child!,
          ),
          home: _Host(
            opener: opener,
            dialog: AppDialog(
              icon: Icons.inventory_2_outlined,
              title: 'Add a product to the catalogue',
              subtitle: 'Step 2 of 3: how is this product sold?',
              width: 600,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  DialogSectionLabel('Selling units'),
                  FormStepHeader(step: 2, title: 'How is this product sold?'),
                  TextField(
                    decoration: InputDecoration(labelText: 'Base unit'),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(labelText: 'Base price'),
                  ),
                  SizedBox(height: 12),
                  InfoBanner(
                    message:
                        'Stock arrives through a purchase order, then Receiving.',
                  ),
                  SizedBox(height: 12),
                  DetailRow(label: 'Supplier', value: 'Cebu Hardware Trading'),
                  TotalBar(label: 'Total', amount: 1234567.89),
                ],
              ),
              actions: [
                TextButton(onPressed: () {}, child: const Text('Cancel')),
                FilledButton(
                  onPressed: () {},
                  child: const Text('Save product'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('New product'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TotalBar), findsOneWidget);
      expect(find.byType(InfoBanner), findsOneWidget);
    });
  });
}
