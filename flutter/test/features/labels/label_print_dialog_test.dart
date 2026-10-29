// Phase 6 Task 6 (decision 14): the label dialog.
//
// Two things must hold no matter what the user types: the copies field is the only
// thing that decides the page count, and an invalid number generates NOTHING (a
// 10 000-page accidental print is a real roll of labels and a jammed printer).
// The printing plugin is behind [LabelPrinter], so these assertions about the
// requests are the same thing as assertions about the PDF.

import 'package:client/features/labels/label_document.dart';
import 'package:client/features/labels/label_print_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingPrinter implements LabelPrinter {
  final List<List<LabelRequest>> printed = [];
  final List<List<LabelRequest>> saved = [];

  @override
  Future<void> print(List<LabelRequest> requests) async {
    printed.add(requests);
  }

  @override
  Future<void> savePdf(List<LabelRequest> requests) async {
    saved.add(requests);
  }
}

LabelRequest request({
  String code = 'QB000013-0',
  String unitName = 'PC',
  int copies = 1,
}) => LabelRequest(
  code: code,
  productName: 'Circuit Breaker',
  variantName: '20A 1-pole',
  unitName: unitName,
  copies: copies,
);

Future<void> _openDialog(
  WidgetTester tester, {
  required List<LabelRequest> requests,
  required _RecordingPrinter printer,
  bool allowSkip = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => LabelPrintDialog(
                requests: requests,
                printer: printer,
                allowSkip: allowSkip,
              ),
            ),
            child: const Text('open labels'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open labels'));
  await tester.pumpAndSettle();
}

void main() {
  late _RecordingPrinter printer;

  setUp(() => printer = _RecordingPrinter());

  testWidgets('a factory-EAN unit is listed as skipped and gets no field', (
    tester,
  ) async {
    await _openDialog(
      tester,
      requests: [request(), request(code: '4800016123450', unitName: 'BOX')],
      printer: printer,
    );

    expect(find.text('Factory barcode — skipped'), findsOneWidget);
    expect(
      find.byType(TextFormField),
      findsOneWidget,
      reason: 'only the QB unit takes copies',
    );
  });

  testWidgets('the copies typed are the copies printed', (tester) async {
    await _openDialog(tester, requests: [request()], printer: printer);

    await tester.enterText(find.byType(TextFormField), '3');
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(printer.printed, hasLength(1));
    expect(printer.printed.single.single.copies, 3);
    expect(printer.saved, isEmpty);
  });

  testWidgets('Save PDF hands the same requests over, and prints nothing', (
    tester,
  ) async {
    await _openDialog(tester, requests: [request(copies: 2)], printer: printer);

    await tester.tap(find.text('Save PDF'));
    await tester.pumpAndSettle();

    expect(printer.saved, hasLength(1));
    expect(printer.saved.single.single.copies, 2);
    expect(printer.printed, isEmpty);
  });

  testWidgets('0 copies is refused: nothing is generated', (tester) async {
    await _openDialog(tester, requests: [request()], printer: printer);

    await tester.enterText(find.byType(TextFormField), '0');
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(printer.printed, isEmpty);
    expect(printer.saved, isEmpty);
    expect(find.byType(TextFormField), findsOneWidget, reason: 'dialog stays');
  });

  testWidgets('201 copies is refused: nothing is generated', (tester) async {
    await _openDialog(tester, requests: [request()], printer: printer);

    await tester.enterText(find.byType(TextFormField), '201');
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(printer.printed, isEmpty);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('a non-number is refused: nothing is generated', (tester) async {
    await _openDialog(tester, requests: [request()], printer: printer);

    await tester.enterText(find.byType(TextFormField), 'abc');
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(printer.printed, isEmpty);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('skip-allowed: a 0 row is skipped, the others still print', (
    tester,
  ) async {
    // The Receiving pre-fill uses 0 for the units a delivery did not arrive as.
    await _openDialog(
      tester,
      requests: [request(copies: 4), request(code: 'QB000012-3', copies: 0)],
      printer: printer,
      allowSkip: true,
    );

    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(printer.printed, hasLength(1));
    final sent = printer.printed.single;
    expect(sent, hasLength(1), reason: 'the 0-copy unit is skipped');
    expect(sent.single.code, 'QB000013-0');
    expect(sent.single.copies, 4);
  });

  testWidgets('every row at 0 prints nothing and says why', (tester) async {
    await _openDialog(
      tester,
      requests: [request(copies: 0)],
      printer: printer,
      allowSkip: true,
    );

    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(printer.printed, isEmpty);
    expect(find.textContaining('Choose at least one copy'), findsOneWidget);
  });
}
