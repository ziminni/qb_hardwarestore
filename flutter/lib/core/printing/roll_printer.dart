import 'dart:typed_data';

import 'package:client/core/printing/escpos.dart';
import 'package:client/core/printing/raw_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

const rollPrinterKey = 'roll_printer_id';
const rollPrinterNameKey = 'roll_printer_name';

/// What a print says when this computer has no receipt printer yet.
const noReceiptPrinterMessage =
    'No receipt printer is set on this computer. The cashier chooses it in '
    'the till\'s Settings tab.';

/// The counter's receipt printer: chosen once in the till's Settings tab,
/// then every receipt goes straight to it as raw ESC/POS, with no dialog and
/// no driver in between.
class RollPrinter {
  RollPrinter({RawPrinter? raw}) : _raw = raw ?? platformRawPrinter();

  final RawPrinter _raw;

  /// Every printer this computer knows, for Settings to choose from.
  Future<List<RawPrinterInfo>> printers() => _raw.printers();

  /// Sends [bytes] to the saved receipt printer. Throws [PrinterException]
  /// when none is saved, so nothing is guessed and nothing is asked.
  Future<void> print(Uint8List bytes, {required String job}) async {
    final printer = await saved();
    if (printer == null) throw const PrinterException(noReceiptPrinterMessage);
    await _raw.send(printer.id, bytes, job: job);
  }

  /// The receipt printer saved on this computer, or null.
  static Future<RawPrinterInfo?> saved() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(rollPrinterKey);
    if (id == null) return null;
    return RawPrinterInfo(
      id: id,
      name: prefs.getString(rollPrinterNameKey) ?? id,
    );
  }

  /// Makes [printer] this computer's receipt printer.
  static Future<void> choose(RawPrinterInfo printer) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(rollPrinterKey, printer.id);
    await prefs.setString(rollPrinterNameKey, printer.name);
  }

  static const autoPrintKey = 'receipt_auto_print';

  /// Whether a sale's receipt prints by itself once the sale is recorded
  /// (owner 2026-11-19). On unless the cashier turned it off in Settings.
  static Future<bool> autoPrint() async =>
      (await SharedPreferences.getInstance()).getBool(autoPrintKey) ?? true;

  static Future<void> setAutoPrint(bool on) async =>
      (await SharedPreferences.getInstance()).setBool(autoPrintKey, on);

  /// Clears the receipt printer on this computer.
  static Future<void> forget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(rollPrinterKey);
    await prefs.remove(rollPrinterNameKey);
  }
}

/// A short test strip: proves the chosen printer reads the job, on a few
/// lines of paper.
Uint8List buildTestPrintEscPos(String printerName, DateTime at) {
  final job = EscPosJob()
    ..text('QUEEN BUILDERS', bold: true, center: true, large: true)
    ..text('Receipt printer test', center: true)
    ..divider()
    ..text('Printer: $printerName')
    ..text(
      'Time: ${at.year}-${_two(at.month)}-${_two(at.day)} '
      '${_two(at.hour)}:${_two(at.minute)}',
    )
    ..divider()
    ..text('If you can read this, receipts will print here.', center: true);
  return job.finish();
}

String _two(int value) => value.toString().padLeft(2, '0');
