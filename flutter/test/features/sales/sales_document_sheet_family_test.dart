// Phase 1d Task 10b (decisions 16-17): the shared document sheet, the one every
// role reads a sale, a quotation, an order or a return through, joins the dialog
// family: a hexagon header, label/value rows and the gold total bar. It stays a
// bottom sheet and stays strictly read-only.
//
// What must not change: the customer, status and per-line information the pages
// hand it, the "No items" sentence, and that there is nothing to press (D-02:
// View is a display action, so no field and no submit button).

import 'dart:io';

import 'package:client/core/format/format.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    ('OpenSans', ['OpenSans-Regular.ttf', 'OpenSans-Bold.ttf']),
    ('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(bytes.buffer.asByteData()));
    }
    await loader.load();
  }
}

const _fields = <(String, String)>[
  ('Date', 'Oct 30, 2026'),
  ('Customer', 'Reyes Trading'),
  ('Cashier', 'Ana Lopez'),
  ('Status', 'Completed'),
];

List<SalesDocumentLine> _lines() => const [
  SalesDocumentLine(name: 'Portland Cement 40kg', qty: 1200, unitPrice: 950),
  SalesDocumentLine(name: '10 mm x 6 m', qty: 40, unitPrice: 240),
];

void main() {
  setUpAll(_loadAppFonts);

  Future<FocusNode> open(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
    double scale = 1.0,
    List<SalesDocumentLine>? lines,
    num total = 1149600,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);

    final opener = FocusNode(debugLabel: 'opener');
    addTearDown(opener.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: Focus(
              focusNode: opener,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showSalesDocumentSheet(
                    context,
                    title: 'TRX-20261030-0002',
                    fields: _fields,
                    lines: lines ?? _lines(),
                    total: total,
                  ),
                  child: const Text('View'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    opener.requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    return opener;
  }

  testWidgets('it is still a sheet, with the hexagon header and the document '
      'title once', (tester) async {
    await open(tester);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(SalesDocumentSheet), findsOneWidget);
    final title = tester.widget<Text>(find.text('TRX-20261030-0002'));
    expect(title.style?.fontFamily, 'Cinzel');
    expect(title.style!.fontSize!, greaterThanOrEqualTo(18));
    expect(find.byType(HexIconBadge), findsOneWidget);
  });

  testWidgets('customer, status and every line are still on the document', (
    tester,
  ) async {
    await open(tester);

    // Each field is a label/value row of the family.
    expect(find.byType(DetailRow), findsNWidgets(_fields.length));
    expect(find.text('Customer'), findsOneWidget);
    expect(find.text('Reyes Trading'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('ITEMS'), findsOneWidget);
    for (final line in _lines()) {
      expect(find.text(line.name), findsOneWidget);
      expect(
        find.text('${salesQty(line.qty)} × ${formatPeso(line.unitPrice)}'),
        findsOneWidget,
      );
      expect(find.text(formatPeso(line.subtotal)), findsOneWidget);
    }
    expect(find.textContaining('—'), findsNothing);
  });

  testWidgets('the total is the gold bar, showing what the page handed in', (
    tester,
  ) async {
    await open(tester);

    final bar = tester.widget<TotalBar>(find.byType(TotalBar));
    expect(bar.label, 'Total');
    expect(
      bar.amount,
      1149600,
      reason: 'the page hands the number straight to the bar, unformatted',
    );
    expect(find.text('₱1,149,600.00'), findsOneWidget);
  });

  testWidgets('a negative total keeps its sign and grouping', (tester) async {
    await open(tester, total: -1140000);

    final bar = tester.widget<TotalBar>(find.byType(TotalBar));
    expect(bar.amount, -1140000);
    expect(find.text('-₱1,140,000.00'), findsOneWidget);
  });

  testWidgets('strictly read-only: no field, no submit button', (tester) async {
    await open(tester);

    expect(
      find.descendant(
        of: find.byType(SalesDocumentSheet),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(SalesDocumentSheet),
        matching: find.byType(TextButton),
      ),
      findsNothing,
    );
  });

  testWidgets('a document with no items still says so', (tester) async {
    await open(tester, lines: const []);

    expect(find.text('No items'), findsOneWidget);
  });

  testWidgets('Esc closes the sheet', (tester) async {
    await open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(SalesDocumentSheet), findsNothing);
  });

  for (final (width, scale) in const [
    (1440.0, 1.0),
    (1100.0, 1.0),
    (760.0, 1.3),
  ]) {
    testWidgets('lays out at ${width.toInt()} px, text scale $scale', (
      tester,
    ) async {
      await open(tester, size: Size(width, 1000), scale: scale);

      expect(tester.takeException(), isNull);
      expect(find.text('Reyes Trading'), findsOneWidget);
      expect(find.byType(TotalBar), findsOneWidget);
      final rect = tester.getRect(find.byType(SalesDocumentSheet));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(width));
    });
  }

  testWidgets('a long line name does not overflow at 760 px and 1.3x text', (
    tester,
  ) async {
    await open(
      tester,
      size: const Size(760, 1000),
      scale: 1.3,
      lines: const [
        SalesDocumentLine(
          name:
              'Deformed Steel Bar 10 mm x 6 m Grade 60 (cut and bent to '
              'schedule)',
          qty: 12,
          unitPrice: 240,
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(TotalBar), findsOneWidget);
  });
}
