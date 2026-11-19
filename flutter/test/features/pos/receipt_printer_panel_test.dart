// Settings, Receipt printer (2026-11-18): the one place the counter's receipt
// printer is chosen, so a receipt prints with no picker and no dialog.

import 'dart:typed_data';

import 'package:client/core/printing/raw_printer.dart';
import 'package:client/core/printing/roll_printer.dart';
import 'package:client/features/pos/widgets/receipt_printer_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/escpos_reader.dart';

class _FakeRaw implements RawPrinter {
  _FakeRaw(this.list);
  final List<RawPrinterInfo> list;
  final sent = <(String, Uint8List)>[];

  @override
  Future<List<RawPrinterInfo>> printers() async => list;

  @override
  Future<void> send(
    String printerId,
    Uint8List bytes, {
    required String job,
  }) async => sent.add((printerId, bytes));
}

const _thermal = RawPrinterInfo(
  id: 'GEZHI_micro_printer',
  name: 'GEZHI micro-printer',
);
const _inkjet = RawPrinterInfo(
  id: 'EPSON_L3210_Series',
  name: 'EPSON L3210 Series',
);

Future<void> _pump(WidgetTester tester, RawPrinter raw) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: ReceiptPrinterPanel(raw: raw)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('lists this computer\'s printers and says none is chosen', (
    tester,
  ) async {
    await _pump(tester, _FakeRaw([_inkjet, _thermal]));

    expect(find.text('EPSON L3210 Series'), findsOneWidget);
    expect(find.text('GEZHI micro-printer'), findsOneWidget);
    expect(find.textContaining('No receipt printer chosen'), findsOneWidget);
  });

  testWidgets('choosing a printer saves it for every receipt after', (
    tester,
  ) async {
    await _pump(tester, _FakeRaw([_inkjet, _thermal]));

    await tester.tap(find.text('GEZHI micro-printer'));
    await tester.pumpAndSettle();

    expect(find.text('Receipts print to GEZHI micro-printer.'), findsOneWidget);
    expect((await RollPrinter.saved())?.id, _thermal.id);
  });

  testWidgets('a saved printer shows as chosen when Settings opens', (
    tester,
  ) async {
    await RollPrinter.choose(_thermal);
    await _pump(tester, _FakeRaw([_inkjet, _thermal]));

    expect(find.text('Receipts print to GEZHI micro-printer.'), findsOneWidget);
    final tile = find.byKey(
      const ValueKey('receipt-printer-GEZHI_micro_printer'),
    );
    expect(
      find.descendant(
        of: tile,
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the test print goes to the chosen printer, and only once one is '
      'chosen', (tester) async {
    final raw = _FakeRaw([_thermal]);
    await _pump(tester, raw);

    final button = find.widgetWithText(FilledButton, 'Print test receipt');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.tap(find.text('GEZHI micro-printer'));
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(raw.sent.single.$1, _thermal.id);
    expect(
      escPosLines(raw.sent.single.$2),
      contains('Printer: GEZHI micro-printer'),
    );
    expect(find.text('Test sent to GEZHI micro-printer.'), findsOneWidget);
  });

  testWidgets('no printers says to connect one', (tester) async {
    await _pump(tester, _FakeRaw(const []));

    expect(find.textContaining('No printers found'), findsOneWidget);
  });
}
