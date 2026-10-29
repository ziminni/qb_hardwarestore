// Phase 6 Task 6 (decision 14): the label dialog.
//
// Two things must hold no matter what the user types: the copies field is the only
// thing that decides the page count, and an invalid number generates NOTHING (a
// 10 000-page accidental print is a real roll of labels and a jammed printer).
// The printing plugin is behind [LabelPrinter], so these assertions about the
// requests are the same thing as assertions about the PDF.

import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/labels/delivery_labels.dart';
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

/// The base selling unit a goods receipt restocks.
List<LabelRequest> deliveryReceipt(int receivedQty) => deliveryLabelRequests(
  productName: 'Circuit Breaker',
  variantName: '20A 1-pole',
  sellingUnits: const [
    VariantUom(
      id: 13,
      variantId: 8,
      uomId: 1,
      uomCode: 'PC',
      uomName: 'Piece',
      barcodeQr: 'QB000013-0',
      conversionFactor: 1,
      defaultSellingPrice: 315,
    ),
  ],
  receivedQty: receivedQty.toDouble(),
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
      requests: [
        request(),
        request(code: '4800016123450', unitName: 'BOX'),
      ],
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
      requests: [
        request(copies: 4),
        request(code: 'QB000012-3', copies: 0),
      ],
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

  testWidgets('a receipt over the cap shows 200 AND says it was capped', (
    tester,
  ) async {
    // 2 500 pieces received: the 1..200 ceiling (decision 14) still applies, but a
    // silent clamp under-labels the delivery and nobody notices.
    await _openDialog(
      tester,
      requests: deliveryReceipt(2500),
      printer: printer,
      allowSkip: true,
    );

    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '200',
    );
    expect(
      find.textContaining('capped at 200 labels per print'),
      findsOneWidget,
      reason: 'the clerk must know the delivery needs a second print',
    );
  });

  testWidgets('a receipt under the cap says nothing about a cap', (
    tester,
  ) async {
    await _openDialog(
      tester,
      requests: deliveryReceipt(12),
      printer: printer,
      allowSkip: true,
    );

    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '12',
    );
    expect(find.textContaining('capped at'), findsNothing);
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
