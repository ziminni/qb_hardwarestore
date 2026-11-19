import 'dart:convert';
import 'dart:typed_data';

/// The two IPP requests the app makes of CUPS (macOS and Linux printing), and
/// the one answer it reads. IPP is CUPS' own protocol, over HTTP on port 631.
///
/// The format that matters is `application/vnd.cups-raw` on a print job: CUPS
/// passes such a job to the printer untouched. Without it a queue set up with
/// a "Generic PostScript" driver turns the job into PostScript, and a receipt
/// printer prints the PostScript program as text, metres of it.

const ippRawFormat = 'application/vnd.cups-raw';

const _printJob = 0x0002;
const _cupsGetPrinters = 0x4002;

const _operationGroup = 0x01;
const _printerGroup = 0x04;
const _endOfAttributes = 0x03;

const _tagKeyword = 0x44;
const _tagUri = 0x45;
const _tagCharset = 0x47;
const _tagLanguage = 0x48;
const _tagMimeType = 0x49;
const _tagName = 0x42;

/// A Print-Job request for [queue] with [document] as its raw payload.
Uint8List ippPrintJobRequest({
  required String queue,
  required String jobName,
  required Uint8List document,
  int requestId = 1,
}) {
  final out = _header(_printJob, requestId)
    ..attribute(_tagUri, 'printer-uri', ippPrinterUri(queue))
    ..attribute(_tagName, 'requesting-user-name', 'pos')
    ..attribute(_tagName, 'job-name', jobName)
    ..attribute(_tagMimeType, 'document-format', ippRawFormat)
    ..byte(_endOfAttributes)
    ..bytes(document);
  return out.toBytes();
}

/// A CUPS-Get-Printers request for each queue's name and description.
Uint8List ippGetPrintersRequest({int requestId = 1}) {
  final out = _header(_cupsGetPrinters, requestId)
    ..attribute(_tagKeyword, 'requested-attributes', 'printer-name')
    ..additionalValue(_tagKeyword, 'printer-info')
    ..byte(_endOfAttributes);
  return out.toBytes();
}

/// `ipp://localhost/printers/<queue>`, the queue's name escaped for a path.
String ippPrinterUri(String queue) =>
    'ipp://localhost/printers/${Uri.encodeComponent(queue)}';

/// One printer queue as CUPS reports it.
class IppPrinter {
  const IppPrinter({required this.queue, required this.description});

  /// The queue name a job is sent to (`GEZHI_micro_printer`).
  final String queue;

  /// What System Settings shows (`GEZHI micro-printer`); the queue name when
  /// CUPS has none.
  final String description;
}

/// The status of an IPP response: 0x0000 to 0x00FF is success.
int ippStatus(Uint8List response) {
  if (response.length < 8) {
    throw const FormatException('IPP response too short');
  }
  return (response[2] << 8) | response[3];
}

/// The printers in a CUPS-Get-Printers response, in the order CUPS sent them.
List<IppPrinter> ippParsePrinters(Uint8List response) {
  ippStatus(response);
  final printers = <IppPrinter>[];
  String? queue;
  String? info;
  void close() {
    if (queue case final name?) {
      final description = info ?? '';
      printers.add(
        IppPrinter(
          queue: name,
          description: description.isEmpty ? name : description,
        ),
      );
    }
    queue = null;
    info = null;
  }

  var group = 0;
  var lastName = '';
  var i = 8;
  while (i < response.length) {
    final tag = response[i++];
    if (tag < 0x10) {
      // A delimiter: a new group starts, or the attributes end.
      if (group == _printerGroup) close();
      if (tag == _endOfAttributes) break;
      group = tag;
      continue;
    }
    final nameLength = _u16(response, i);
    i += 2;
    final name = nameLength == 0
        ? lastName
        : utf8.decode(response.sublist(i, i + nameLength));
    i += nameLength;
    final valueLength = _u16(response, i);
    i += 2;
    final value = response.sublist(i, i + valueLength);
    i += valueLength;
    lastName = name;
    if (group != _printerGroup || nameLength == 0) continue;
    if (name == 'printer-name') queue = utf8.decode(value);
    if (name == 'printer-info') info = utf8.decode(value);
  }
  if (group == _printerGroup) close();
  return printers;
}

int _u16(Uint8List data, int at) {
  if (at + 2 > data.length) {
    throw const FormatException('IPP response cut short');
  }
  return (data[at] << 8) | data[at + 1];
}

_IppWriter _header(int operation, int requestId) => _IppWriter()
  ..bytes([0x02, 0x00]) // IPP 2.0
  ..u16(operation)
  ..u32(requestId)
  ..byte(_operationGroup)
  ..attribute(_tagCharset, 'attributes-charset', 'utf-8')
  ..attribute(_tagLanguage, 'attributes-natural-language', 'en');

class _IppWriter {
  final _out = BytesBuilder();

  void byte(int value) => _out.addByte(value);
  void bytes(List<int> value) => _out.add(value);
  void u16(int value) => _out.add([(value >> 8) & 0xFF, value & 0xFF]);
  void u32(int value) => _out.add([
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);

  void attribute(int tag, String name, String value) {
    final nameBytes = utf8.encode(name);
    final valueBytes = utf8.encode(value);
    byte(tag);
    u16(nameBytes.length);
    bytes(nameBytes);
    u16(valueBytes.length);
    bytes(valueBytes);
  }

  /// A second value of the attribute just written (an empty name).
  void additionalValue(int tag, String value) {
    final valueBytes = utf8.encode(value);
    byte(tag);
    u16(0);
    u16(valueBytes.length);
    bytes(valueBytes);
  }

  Uint8List toBytes() => _out.toBytes();
}
