// Printing through CUPS (macOS, Linux) as a RAW job (2026-11-18). The Mac had
// the receipt printer set up with a "Generic PostScript Printer" driver, so a
// normal job reached it as PostScript and printed as text. Marking the job
// `application/vnd.cups-raw` makes CUPS hand the ESC/POS bytes over untouched.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:client/core/printing/ipp.dart';
import 'package:client/core/printing/raw_printer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every (name, value) in an IPP request's operation group, in order.
List<(String, String)> _attributes(Uint8List request) {
  final out = <(String, String)>[];
  var i = 9; // version, operation, request id, group tag
  var last = '';
  while (request[i] != 0x03) {
    i += 1;
    final nameLength = (request[i] << 8) | request[i + 1];
    i += 2;
    final name = nameLength == 0
        ? last
        : utf8.decode(request.sublist(i, i + nameLength));
    i += nameLength;
    final valueLength = (request[i] << 8) | request[i + 1];
    i += 2;
    out.add((name, utf8.decode(request.sublist(i, i + valueLength))));
    i += valueLength;
    last = name;
  }
  return out;
}

Uint8List _response(
  int status, [
  List<(int, String, String)> printerRows = const [],
]) {
  final out = BytesBuilder()
    ..add([0x02, 0x00, status >> 8, status & 0xFF, 0, 0, 0, 1])
    ..addByte(0x01);
  void attribute(int tag, String name, String value) {
    final n = utf8.encode(name);
    final v = utf8.encode(value);
    out
      ..addByte(tag)
      ..add([n.length >> 8, n.length & 0xFF])
      ..add(n)
      ..add([v.length >> 8, v.length & 0xFF])
      ..add(v);
  }

  attribute(0x47, 'attributes-charset', 'utf-8');
  var group = -1;
  for (final (index, name, value) in printerRows) {
    if (index != group) {
      out.addByte(0x04);
      group = index;
    }
    attribute(name == 'printer-name' ? 0x42 : 0x41, name, value);
  }
  out.addByte(0x03);
  return out.toBytes();
}

void main() {
  test('a print job is marked raw so CUPS passes the bytes untouched', () {
    final document = Uint8List.fromList([0x1B, 0x40, 0x41, 0x0A]);
    final request = ippPrintJobRequest(
      queue: 'GEZHI_micro_printer',
      jobName: 'OR-1',
      document: document,
    );

    expect(request.take(4), [0x02, 0x00, 0x00, 0x02]); // IPP 2.0 Print-Job
    final attributes = _attributes(request);
    expect(
      attributes,
      contains(('document-format', 'application/vnd.cups-raw')),
    );
    expect(
      attributes,
      contains(('printer-uri', 'ipp://localhost/printers/GEZHI_micro_printer')),
    );
    expect(attributes, contains(('job-name', 'OR-1')));
    // The document follows the end-of-attributes tag, byte for byte.
    expect(request.sublist(request.length - document.length), document);
    expect(request[request.length - document.length - 1], 0x03);
  });

  test('the printer list reads each queue and its description', () {
    final printers = ippParsePrinters(
      _response(0, [
        (0, 'printer-name', 'GEZHI_micro_printer'),
        (0, 'printer-info', 'GEZHI micro-printer'),
        (1, 'printer-name', 'EPSON_L3210_Series'),
      ]),
    );

    expect(printers.map((p) => (p.queue, p.description)), [
      ('GEZHI_micro_printer', 'GEZHI micro-printer'),
      ('EPSON_L3210_Series', 'EPSON_L3210_Series'),
    ]);
  });

  group('CupsRawPrinter over HTTP', () {
    late HttpServer server;
    final received = <(String, String?, Uint8List)>[];
    var answer = _response(0);

    setUp(() async {
      received.clear();
      answer = _response(0);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await request.fold<BytesBuilder>(
          BytesBuilder(),
          (out, chunk) => out..add(chunk),
        );
        received.add((
          request.uri.path,
          request.headers.contentType?.mimeType,
          body.toBytes(),
        ));
        request.response
          ..headers.contentType = ContentType('application', 'ipp')
          ..add(answer);
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    CupsRawPrinter printer() => CupsRawPrinter(
      host: '127.0.0.1',
      port: server.port,
      socketPaths: const [],
    );

    test('a job is posted to its queue as an IPP request', () async {
      final bytes = Uint8List.fromList([0x1B, 0x40]);
      await printer().send('GEZHI_micro_printer', bytes, job: 'OR-1');

      final (path, type, body) = received.single;
      expect(path, '/printers/GEZHI_micro_printer');
      expect(type, 'application/ipp');
      expect(
        body,
        ippPrintJobRequest(
          queue: 'GEZHI_micro_printer',
          jobName: 'OR-1',
          document: bytes,
        ),
      );
    });

    test('a refused job is an error the cashier sees', () async {
      answer = _response(0x0406); // client-error-not-found
      await expectLater(
        printer().send('gone', Uint8List(0), job: 'OR-1'),
        throwsA(isA<PrinterException>()),
      );
    });

    test('a missing socket file falls back to TCP', () async {
      final printers = CupsRawPrinter(
        host: '127.0.0.1',
        port: server.port,
        socketPaths: const ['/nonexistent/cupsd.sock'],
      );
      await printers.send('Q', Uint8List(0), job: 'OR-1');

      expect(received.single.$1, '/printers/Q');
    });

    test('the printer list comes from CUPS', () async {
      answer = _response(0, [(0, 'printer-name', 'GEZHI_micro_printer')]);
      final printers = await printer().printers();

      expect(printers.single.id, 'GEZHI_micro_printer');
      expect(received.single.$1, '/');
    });
  });

  // macOS wakes CUPS only through its socket file; port 631 is closed while
  // CUPS is idle, which is when the first print of the day happens.
  test('CUPS is reached through its socket file first', () async {
    final dir = await Directory.systemTemp.createTemp('cups');
    final path = '${dir.path}/cupsd';
    final server = await HttpServer.bind(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    final paths = <String>[];
    server.listen((request) async {
      paths.add(request.uri.path);
      await request.drain<void>();
      request.response.add(_response(0));
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await dir.delete(recursive: true);
    });

    // Port 9 (discard) is closed: only the socket file can answer.
    await CupsRawPrinter(
      port: 9,
      socketPaths: [path],
    ).send('GEZHI_micro_printer', Uint8List(0), job: 'OR-1');

    expect(paths, ['/printers/GEZHI_micro_printer']);
  });
}
