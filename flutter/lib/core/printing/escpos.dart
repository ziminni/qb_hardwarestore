import 'dart:typed_data';

/// Characters a line holds on a 58 mm roll in the printer's default font
/// (384 dots / 12 dots a character), the GOOJPRT PT-210 and its kin.
const roll58Columns = 32;

/// Lines fed after the last text, so the tear bar clears it. The feed is the
/// ONLY paper the job asks for beyond its own lines: a fixed amount, never "to
/// the end of the page", which is how a PDF with no page length ran a roll out.
const tearOffFeedLines = 4;

/// QR size: 8 dots a module. A thermal head prints 8 dots a millimetre, so an
/// OR number's 25-module code comes out about 25 mm square: big enough for the
/// Bodega Checker's phone camera, and well inside the 48 mm print width.
const qrModuleDots = 8;

/// Lines a QR is counted as toward [maxJobLines]: 25 modules x 8 dots is 200
/// dots, about 8 lines of 24 dots, rounded up.
const qrLines = 10;

/// Longest QR payload accepted; an OR number is far shorter.
const maxQrLength = 64;

/// A ceiling on one job's lines. A real receipt is far below it; anything over
/// is a bug, refused before a byte reaches the printer.
const maxJobLines = 600;

/// ESC/POS commands for one receipt-printer job.
///
/// Thermal receipt printers speak ESC/POS, not PDF or PostScript: handed a
/// document they cannot read, they print its bytes as text. So the job is built
/// as the printer's own commands and sent raw (see `RawPrinter`).
///
/// Text is reduced to printable ASCII ([sanitize]): the printer's code page is
/// not UTF-8, and a control byte inside a name or an address would otherwise be
/// read as a command.
class EscPosJob {
  EscPosJob({this.columns = roll58Columns}) {
    _out.add(const [0x1B, 0x40]); // ESC @: reset to the default state.
  }

  final int columns;
  final BytesBuilder _out = BytesBuilder();
  int _lines = 0;

  /// The lines printed so far, feed included.
  int get lineCount => _lines;

  /// One block of text, wrapped to the roll.
  void text(
    String value, {
    bool bold = false,
    bool center = false,
    bool large = false,
  }) {
    final width = large ? columns ~/ 2 : columns;
    _style(bold: bold, center: center, large: large);
    for (final line in wrap(sanitize(value), width)) {
      _line(line);
    }
    _style();
  }

  /// [label] on the left and [value] flush right, the label wrapping above
  /// when both do not fit on one line.
  void row(String label, String value, {bool bold = false}) {
    _style(bold: bold);
    final right = sanitize(value);
    final left = wrap(sanitize(label), columns);
    for (final line in left.take(left.length - 1)) {
      _line(line);
    }
    final last = left.last;
    final gap = columns - last.length - right.length;
    if (gap >= 1) {
      _line('$last${' ' * gap}$right');
    } else {
      _line(last);
      _line(right.padLeft(columns));
    }
    _style();
  }

  /// A full-width rule.
  void divider() => _line('-' * columns);

  /// A QR code of [data], centred, through the printer's own QR command
  /// (`GS ( k`, model 2, error level M). Lines counted as [qrLines].
  void qr(String data) {
    final payload = sanitize(data).codeUnits;
    if (payload.isEmpty || payload.length > maxQrLength) {
      throw ArgumentError.value(
        data,
        'data',
        'QR data must be 1 to $maxQrLength characters',
      );
    }
    _style(center: true);
    _qrCommand([0x31, 0x41, 0x32, 0x00]); // model 2
    _qrCommand([0x31, 0x43, qrModuleDots]); // dots per module
    _qrCommand([0x31, 0x45, 0x31]); // error correction M
    _qrCommand([0x31, 0x50, 0x30, ...payload]); // store the data
    _qrCommand([0x31, 0x51, 0x30]); // print it
    _out.addByte(0x0A);
    _count(qrLines);
    _style();
  }

  void _qrCommand(List<int> body) {
    // GS ( k pL pH, then the body; pL/pH is the body's length.
    _out.add([0x1D, 0x28, 0x6B, body.length & 0xFF, body.length >> 8, ...body]);
  }

  /// [lines] blank lines, through ESC d so the printer counts them itself.
  void feed(int lines) {
    if (lines <= 0) return;
    _out.add([0x1B, 0x64, lines]); // ESC d n: print and feed n lines.
    _count(lines);
  }

  /// The job's bytes, ending with the fixed tear-off feed.
  Uint8List finish() {
    feed(tearOffFeedLines);
    return _out.toBytes();
  }

  void _line(String line) {
    _out.add(line.codeUnits);
    _out.addByte(0x0A); // LF: print the line and advance one.
    _count(1);
  }

  void _count(int lines) {
    _lines += lines;
    if (_lines > maxJobLines) {
      throw StateError('Print job over $maxJobLines lines; refused.');
    }
  }

  void _style({bool bold = false, bool center = false, bool large = false}) {
    _out.add([0x1B, 0x45, bold ? 1 : 0]); // ESC E n: bold on or off.
    _out.add([0x1B, 0x61, center ? 1 : 0]); // ESC a n: left or centre.
    _out.add([0x1D, 0x21, large ? 0x11 : 0]); // GS ! n: double width + height.
  }
}

const _replacements = {
  '₱': 'PHP ',
  '·': '-',
  '×': 'x',
  '–': '-',
  '—': '-',
  '‘': "'",
  '’': "'",
  '“': '"',
  '”': '"',
  'ñ': 'n',
  'Ñ': 'N',
};

/// [value] as printable ASCII: the few typographic characters the app uses
/// become their plain twins, other non-ASCII becomes `?`, and every control
/// character (ESC, GS, newlines inside a field) becomes a space.
String sanitize(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    if (_replacements[char] case final plain?) {
      out.write(plain);
    } else if (rune < 0x20 || rune == 0x7F) {
      out.write(' ');
    } else if (rune > 0x7E) {
      out.write('?');
    } else {
      out.write(char);
    }
  }
  return out.toString();
}

/// [value] split into lines of at most [width] characters, at spaces where it
/// can and mid-word where a word is longer than a line.
List<String> wrap(String value, int width) {
  final lines = <String>[];
  var current = '';
  for (var word in value.split(' ').where((w) => w.isNotEmpty)) {
    while (word.length > width) {
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      lines.add(word.substring(0, width));
      word = word.substring(width);
    }
    if (current.isEmpty) {
      current = word;
    } else if (current.length + 1 + word.length <= width) {
      current = '$current $word';
    } else {
      lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty || lines.isEmpty) lines.add(current);
  return lines;
}
