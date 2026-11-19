import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Sends [bytes] to the Windows printer named [printer] as a RAW job, the
/// spooler's way of passing a job to the printer untouched by its driver.
///
/// Returns null on success, or what went wrong. Only ever called on Windows:
/// the libraries load on first use, so other platforms never open them.
String? windowsSpoolRaw(String printer, String job, Uint8List bytes) {
  if (!Platform.isWindows) return 'Not running on Windows.';
  return using((arena) {
    final handle = arena<Pointer<Void>>();
    if (_openPrinter(
          printer.toNativeUtf16(allocator: arena),
          handle,
          nullptr,
        ) ==
        0) {
      return 'Windows could not open the printer "$printer" '
          '(error ${_getLastError()}).';
    }
    final printerHandle = handle.value;
    try {
      final info = arena<_DocInfo1>()
        ..ref.docName = job.toNativeUtf16(allocator: arena)
        ..ref.outputFile = nullptr
        ..ref.datatype = 'RAW'.toNativeUtf16(allocator: arena);
      if (_startDocPrinter(printerHandle, 1, info) == 0) {
        return 'Windows refused the print job (error ${_getLastError()}).';
      }
      try {
        if (_startPagePrinter(printerHandle) == 0) {
          return 'Windows refused the print job (error ${_getLastError()}).';
        }
        final buffer = arena<Uint8>(bytes.length);
        buffer.asTypedList(bytes.length).setAll(0, bytes);
        final written = arena<Uint32>();
        final ok = _writePrinter(
          printerHandle,
          buffer.cast(),
          bytes.length,
          written,
        );
        _endPagePrinter(printerHandle);
        if (ok == 0 || written.value != bytes.length) {
          return 'Windows could not send the receipt to the printer '
              '(error ${_getLastError()}).';
        }
        return null;
      } finally {
        _endDocPrinter(printerHandle);
      }
    } finally {
      _closePrinter(printerHandle);
    }
  });
}

final class _DocInfo1 extends Struct {
  external Pointer<Utf16> docName;
  external Pointer<Utf16> outputFile;
  external Pointer<Utf16> datatype;
}

final _winspool = DynamicLibrary.open('winspool.drv');
final _kernel32 = DynamicLibrary.open('kernel32.dll');

final _openPrinter = _winspool
    .lookupFunction<
      Int32 Function(Pointer<Utf16>, Pointer<Pointer<Void>>, Pointer<Void>),
      int Function(Pointer<Utf16>, Pointer<Pointer<Void>>, Pointer<Void>)
    >('OpenPrinterW');

final _startDocPrinter = _winspool
    .lookupFunction<
      Uint32 Function(Pointer<Void>, Uint32, Pointer<_DocInfo1>),
      int Function(Pointer<Void>, int, Pointer<_DocInfo1>)
    >('StartDocPrinterW');

final _startPagePrinter = _winspool
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'StartPagePrinter',
    );

final _writePrinter = _winspool
    .lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>, Uint32, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Void>, int, Pointer<Uint32>)
    >('WritePrinter');

final _endPagePrinter = _winspool
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'EndPagePrinter',
    );

final _endDocPrinter = _winspool
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'EndDocPrinter',
    );

final _closePrinter = _winspool
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
      'ClosePrinter',
    );

final _getLastError = _kernel32
    .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
