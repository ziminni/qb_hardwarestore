import 'dart:typed_data';

/// The web build has no spooler; `platformRawPrinter` never picks Windows there.
String? windowsSpoolRaw(String printer, String job, Uint8List bytes) =>
    'Raw printing is not available on this platform.';
