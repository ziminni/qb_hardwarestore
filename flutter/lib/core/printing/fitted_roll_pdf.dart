import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// The page size a built roll document actually came out at: 80 mm wide and
/// as tall as its content, read from the PDF's MediaBox.
///
/// Falls back to an A4-tall strip if the PDF does not state one.
PdfPageFormat fittedRollFormat(Uint8List pdf) {
  final match = RegExp(
    r'/MediaBox\s*\[\s*[\d.]+\s+[\d.]+\s+([\d.]+)\s+([\d.]+)\s*\]',
  ).firstMatch(String.fromCharCodes(pdf));
  if (match == null) {
    return PdfPageFormat(PdfPageFormat.roll80.width, PdfPageFormat.a4.height);
  }
  return PdfPageFormat(
    double.parse(match.group(1)!),
    double.parse(match.group(2)!),
  );
}

/// Prints a roll document through the OS print dialog at its real size.
///
/// The roll formats have an infinite height; handed to the macOS dialog that
/// became an 80 × 2,147,483,647 mm page, and the preview collapsed the lines
/// onto each other. Building first and passing the fitted size avoids it.
Future<void> printFittedRollPdf({
  required String name,
  required Future<Uint8List> Function() build,
}) async {
  final pdf = await build();
  await Printing.layoutPdf(
    name: name,
    format: fittedRollFormat(pdf),
    dynamicLayout: false,
    onLayout: (_) async => pdf,
  );
}
