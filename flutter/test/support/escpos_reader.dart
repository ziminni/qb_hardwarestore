import 'dart:typed_data';

/// What a 58 mm printer would put on paper for [bytes], one string a line,
/// with the style commands `EscPosJob` writes skipped, each `ESC d n` feed
/// read as n blank lines, and a QR code as `[QR <data>]`.
///
/// Throws on any command it does not know, so a test fails rather than
/// guessing when the job gains a command the printer might not support.
List<String> escPosLines(Uint8List bytes) {
  final lines = <String>[];
  final current = StringBuffer();
  var qrData = '';
  var i = 0;
  while (i < bytes.length) {
    final byte = bytes[i];
    if (byte == 0x1B && i + 1 < bytes.length && bytes[i + 1] == 0x40) {
      i += 2; // ESC @
    } else if (byte == 0x1B && i + 2 < bytes.length) {
      final command = bytes[i + 1];
      if (command == 0x64) {
        lines.add(current.toString());
        current.clear();
        lines.addAll(List.filled(bytes[i + 2] - 1, ''));
      } else if (command != 0x45 && command != 0x61) {
        throw FormatException(
          'Unknown ESC command 0x${command.toRadixString(16)}',
        );
      }
      i += 3;
    } else if (byte == 0x1D && i + 2 < bytes.length && bytes[i + 1] == 0x21) {
      i += 3; // GS ! n
    } else if (byte == 0x1D &&
        i + 4 < bytes.length &&
        bytes[i + 1] == 0x28 &&
        bytes[i + 2] == 0x6B) {
      // GS ( k: a QR function. The stored data is read back as one line,
      // `[QR <data>]`, when the print function follows.
      final length = bytes[i + 3] | (bytes[i + 4] << 8);
      final body = bytes.sublist(i + 5, i + 5 + length);
      if (body.length >= 3 && body[1] == 0x50) {
        qrData = String.fromCharCodes(body.skip(3));
      } else if (body.length >= 2 && body[1] == 0x51) {
        lines.add('[QR $qrData]');
      }
      i += 5 + length;
    } else if (byte == 0x0A) {
      lines.add(current.toString());
      current.clear();
      i += 1;
    } else if (byte < 0x20 || byte > 0x7E) {
      throw FormatException('Byte 0x${byte.toRadixString(16)} would not print');
    } else {
      current.writeCharCode(byte);
      i += 1;
    }
  }
  if (current.isNotEmpty) lines.add(current.toString());
  return lines;
}

/// The `n` of the job's last `ESC d n`: the paper fed after the last text.
int escPosFinalFeed(Uint8List bytes) {
  final n = bytes.length;
  if (n < 3 || bytes[n - 3] != 0x1B || bytes[n - 2] != 0x64) {
    throw const FormatException('The job does not end with a fixed feed');
  }
  return bytes[n - 1];
}
