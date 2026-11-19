// The counter's receipt printer (2026-11-18): chosen once in Settings, then
// every receipt goes straight to it with no picker and no print dialog.

import 'dart:typed_data';

import 'package:client/core/printing/raw_printer.dart';
import 'package:client/core/printing/roll_printer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/escpos_reader.dart';

class _FakeRaw implements RawPrinter {
  final sent = <(String, Uint8List)>[];
  bool fail = false;

  @override
  Future<List<RawPrinterInfo>> printers() async => const [];

  @override
  Future<void> send(
    String printerId,
    Uint8List bytes, {
    required String job,
  }) async {
    if (fail) throw const PrinterException('offline');
    sent.add((printerId, bytes));
  }
}

const _thermal = RawPrinterInfo(
  id: 'GEZHI_micro_printer',
  name: 'GEZHI micro-printer',
);

void main() {
  final job = Uint8List.fromList([0x1B, 0x40]);
  late _FakeRaw raw;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    raw = _FakeRaw();
  });

  test('with no printer chosen, a print sends nothing and says where to '
      'choose one', () async {
    await expectLater(
      RollPrinter(raw: raw).print(job, job: 'OR-1'),
      throwsA(
        isA<PrinterException>().having(
          (e) => e.message,
          'message',
          contains('Settings'),
        ),
      ),
    );
    expect(raw.sent, isEmpty);
  });

  test('a chosen printer gets every job, with nothing asked', () async {
    await RollPrinter.choose(_thermal);
    await RollPrinter(raw: raw).print(job, job: 'OR-1');
    await RollPrinter(raw: raw).print(job, job: 'OR-2');

    expect(raw.sent.map((s) => s.$1), [_thermal.id, _thermal.id]);
    expect(raw.sent.first.$2, job);
  });

  test('the choice keeps its name for Settings to show', () async {
    await RollPrinter.choose(_thermal);
    final saved = await RollPrinter.saved();

    expect((saved?.id, saved?.name), (_thermal.id, _thermal.name));
  });

  test(
    'a failed job keeps the choice: the next print tries it again',
    () async {
      await RollPrinter.choose(_thermal);
      raw.fail = true;
      await expectLater(
        RollPrinter(raw: raw).print(job, job: 'OR-1'),
        throwsA(isA<PrinterException>()),
      );

      expect((await RollPrinter.saved())?.id, _thermal.id);
    },
  );

  test('forget clears the choice', () async {
    await RollPrinter.choose(_thermal);
    await RollPrinter.forget();

    expect(await RollPrinter.saved(), isNull);
  });

  test('the test strip is short ESC/POS naming the printer', () {
    final bytes = buildTestPrintEscPos(
      'GEZHI micro-printer',
      DateTime(2026, 11, 18, 19, 5),
    );
    final lines = escPosLines(bytes);

    expect(lines, contains('Printer: GEZHI micro-printer'));
    expect(lines, contains('Time: 2026-11-18 19:05'));
    expect(lines.length, lessThan(20));
  });
}
