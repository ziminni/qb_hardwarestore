import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:client/core/printing/ipp.dart';
import 'package:client/core/printing/windows_spooler_stub.dart'
    if (dart.library.ffi) 'package:client/core/printing/windows_spooler.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

/// A printer the app can send a job to.
class RawPrinterInfo {
  const RawPrinterInfo({required this.id, required this.name});

  /// What a job is addressed to: the CUPS queue, or the Windows printer name.
  final String id;

  /// What the person picks from.
  final String name;
}

/// Sends a job's bytes to a printer exactly as given, past any driver.
///
/// A receipt printer is handed its own ESC/POS commands. Going through the OS
/// print dialog instead lets a driver (often a generic one) rewrite the job
/// into something the printer cannot read and prints as text.
abstract class RawPrinter {
  Future<List<RawPrinterInfo>> printers();

  Future<void> send(String printerId, Uint8List bytes, {required String job});
}

/// The one for this platform: the Windows spooler, or CUPS (macOS, Linux).
RawPrinter platformRawPrinter() {
  if (kIsWeb) return const _NoRawPrinter();
  if (Platform.isWindows) return const WindowsRawPrinter();
  return CupsRawPrinter();
}

/// Where CUPS listens on this computer: its local socket file first, then TCP.
///
/// macOS starts CUPS on demand only through `/private/var/run/cupsd`; port 631
/// answers just while it happens to be running, so a first print after CUPS
/// went idle would be refused on TCP alone. Linux names its socket file
/// `/run/cups/cups.sock`.
const cupsSocketPaths = [
  '/private/var/run/cupsd',
  '/run/cups/cups.sock',
  '/var/run/cups/cups.sock',
];

/// CUPS over IPP on this computer, the job marked raw.
class CupsRawPrinter implements RawPrinter {
  CupsRawPrinter({
    this.host = 'localhost',
    this.port = 631,
    this.socketPaths = cupsSocketPaths,
  });

  final String host;
  final int port;

  /// Socket files tried in order before [host]:[port].
  final List<String> socketPaths;

  @override
  Future<List<RawPrinterInfo>> printers() async {
    final response = await _post('/', ippGetPrintersRequest());
    return [
      for (final printer in ippParsePrinters(response))
        RawPrinterInfo(id: printer.queue, name: printer.description),
    ];
  }

  @override
  Future<void> send(
    String printerId,
    Uint8List bytes, {
    required String job,
  }) async {
    final response = await _post(
      '/printers/${Uri.encodeComponent(printerId)}',
      ippPrintJobRequest(queue: printerId, jobName: job, document: bytes),
    );
    final status = ippStatus(response);
    if (status > 0x00FF) {
      throw PrinterException(
        'The printer queue refused the job '
        '(IPP status 0x${status.toRadixString(16).padLeft(4, '0')}).',
      );
    }
  }

  Future<Uint8List> _post(String path, Uint8List body) async {
    final request = await _open(path);
    try {
      request.headers.contentType = ContentType('application', 'ipp');
      request.contentLength = body.length;
      request.add(body);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final data = await response.fold<BytesBuilder>(
        BytesBuilder(),
        (out, chunk) => out..add(chunk),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw PrinterException(
          'The print service answered HTTP ${response.statusCode}.',
        );
      }
      return data.toBytes();
    } on SocketException catch (error) {
      throw PrinterException('The print service stopped answering ($error).');
    } on TimeoutException {
      throw const PrinterException('The print service did not answer.');
    }
  }

  /// A request opened on the first place CUPS answers. Only the CONNECTION is
  /// retried elsewhere: nothing has been sent yet, so no job can print twice.
  Future<HttpClientRequest> _open(String path) async {
    Object? lastError;
    for (final socketPath in [...socketPaths, null]) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      if (socketPath != null) {
        client.connectionFactory = (uri, proxyHost, proxyPort) =>
            Socket.startConnect(
              InternetAddress(socketPath, type: InternetAddressType.unix),
              0,
            );
      }
      try {
        return await client.post(host, port, path);
      } on SocketException catch (error) {
        lastError = error;
        client.close(force: true);
      }
    }
    throw PrinterException(
      'Could not reach the print service on this computer ($lastError).',
    );
  }
}

/// The Windows spooler, the job marked RAW so the driver passes it through.
/// The list comes from the printing plugin, which reads the same spooler.
class WindowsRawPrinter implements RawPrinter {
  const WindowsRawPrinter();

  @override
  Future<List<RawPrinterInfo>> printers() async => [
    for (final printer in await Printing.listPrinters())
      RawPrinterInfo(id: printer.name, name: printer.name),
  ];

  @override
  Future<void> send(
    String printerId,
    Uint8List bytes, {
    required String job,
  }) async {
    final error = windowsSpoolRaw(printerId, job, bytes);
    if (error != null) throw PrinterException(error);
  }
}

class _NoRawPrinter implements RawPrinter {
  const _NoRawPrinter();

  @override
  Future<List<RawPrinterInfo>> printers() async => const [];

  @override
  Future<void> send(String printerId, Uint8List bytes, {required String job}) =>
      throw const PrinterException(
        'Receipt printing needs the desktop app, not the browser.',
      );
}

/// A printing failure in words a cashier can act on.
class PrinterException implements Exception {
  const PrinterException(this.message);
  final String message;

  @override
  String toString() => message;
}
