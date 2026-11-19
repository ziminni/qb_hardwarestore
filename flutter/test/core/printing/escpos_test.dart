// A receipt printer job as ESC/POS (2026-11-18). The first printed receipt went
// through the OS print dialog as a PDF with no page length; a generic driver
// turned it into PostScript and the printer printed that program as text down
// most of a roll. These pin what a job may put on paper: printable ASCII only,
// the roll's width, and a fixed feed at the end.

import 'package:client/core/printing/escpos.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/escpos_reader.dart';

void main() {
  test('a job starts with a reset and ends with the fixed tear-off feed', () {
    final bytes = (EscPosJob()..text('hello')).finish();

    expect(bytes.take(2), [0x1B, 0x40]);
    expect(escPosFinalFeed(bytes), tearOffFeedLines);
    expect(escPosLines(bytes).first, 'hello');
  });

  test('a control byte inside a field is printed as a space, never obeyed', () {
    // ESC @ (reset) and LF typed into an address must not reach the printer as
    // commands: an address could otherwise restyle or feed the paper.
    final bytes = (EscPosJob()..text('12 Mabini\x1B@ St\nCebu')).finish();

    // escPosLines throws on any stray control byte, so reading it back at all
    // proves the ESC never reached the job.
    expect(escPosLines(bytes).first, '12 Mabini @ St Cebu');
  });

  test('typographic characters become plain ASCII, others a question mark', () {
    expect(sanitize('Cement · 40 kg'), 'Cement - 40 kg');
    expect(sanitize('2 bag × PHP 157.50'), '2 bag x PHP 157.50');
    expect(sanitize('₱315.00'), 'PHP 315.00');
    expect(sanitize('Peñafrancia'), 'Penafrancia');
    expect(sanitize('漢'), '?');
  });

  test('no line is wider than the 58 mm roll', () {
    final job = EscPosJob()
      ..text('A very long product name that cannot fit on one line of the roll')
      ..row('Portland Cement Type 1 premium 40 kg', 'PHP 12,345.00')
      ..row('Total', 'PHP 315.00')
      ..text('QUEEN BUILDERS', large: true);

    for (final line in escPosLines(job.finish())) {
      expect(line.length, lessThanOrEqualTo(roll58Columns), reason: line);
    }
  });

  test('a row puts the amount flush right, wrapping a long label above it', () {
    final short = escPosLines(
      (EscPosJob()..row('Total', 'PHP 315.00')).finish(),
    );
    expect(short.first, 'Total${' ' * 17}PHP 315.00');

    final long = escPosLines(
      (EscPosJob()..row('Balance due (held by the cheque) today', 'PHP 1.00'))
          .finish(),
    );
    expect(long.take(2), [
      'Balance due (held by the cheque)',
      'today${' ' * 19}PHP 1.00',
    ]);

    // A label that fills the line exactly leaves no room: the amount drops to
    // its own line, still flush right.
    final full = escPosLines(
      (EscPosJob()..row('Balance due (held by the cheque)', 'PHP 1.00'))
          .finish(),
    );
    expect(full.take(2), [
      'Balance due (held by the cheque)',
      'PHP 1.00'.padLeft(roll58Columns),
    ]);
  });

  test('a runaway job is refused before any byte is sent', () {
    final job = EscPosJob();
    expect(() {
      for (var i = 0; i <= maxJobLines; i++) {
        job.text('line $i');
      }
    }, throwsStateError);
  });

  test('wrap breaks at spaces and splits a word longer than a line', () {
    expect(wrap('one two three', 7), ['one two', 'three']);
    expect(wrap('abcdefghij', 4), ['abcd', 'efgh', 'ij']);
    expect(wrap('', 10), ['']);
  });

  test(
    'a QR goes through the printer QR command, holding exactly the data',
    () {
      final bytes = (EscPosJob()..qr('OR-20261118-0007')).finish();

      expect(escPosLines(bytes).first, '[QR OR-20261118-0007]');
    },
  );

  test('QR data is sanitised and bounded like any other text', () {
    expect(
      escPosLines((EscPosJob()..qr('OR\x1B@1')).finish()).first,
      '[QR OR @1]',
    );
    expect(() => EscPosJob().qr(''), throwsArgumentError);
    expect(() => EscPosJob().qr('x' * (maxQrLength + 1)), throwsArgumentError);
  });
}
