// Phase 3 Task F2: the state behind the import dialog.
//
// Picking a file does two things that can each say no: reading the sheet (a header
// renamed, 2,001 rows, a file that is not a workbook) and the preview call (row
// errors, a stale preview, a refused role). Both end in ONE sentence for the
// clerk, so both land in [error] and the dialog draws one banner.
//
// The parsed rows and the preview's fingerprint stay on this object rather than in
// the dialog, because the next step (B2's apply) posts exactly those two things
// back. Adding it is one method here and one enabled button there, not a rewrite.

import 'package:client/data/models/catalogue_import_preview.dart';
import 'package:client/data/services/catalogue_import_service.dart';
import 'package:client/features/catalogue_io/catalogue_import_sheet.dart';
import 'package:flutter/foundation.dart';

class CatalogueImportViewmodel extends ChangeNotifier {
  CatalogueImportViewmodel({CatalogueImportService? service})
    : _service = service ?? CatalogueImportService();

  final CatalogueImportService _service;

  CatalogueImportPreview? _preview;
  List<CatalogueImportRow> _sheetRows = const [];
  String? _error;
  bool _isPreviewing = false;
  bool _isApplying = false;
  bool _isStale = false;
  CatalogueImportApplied? _applied;
  List<CatalogueImportError> _applyErrors = const [];

  CatalogueImportPreview? get preview => _preview;

  /// The rows the server just read. Kept after a failed preview too: a stale or
  /// refused preview is fixed by previewing THESE rows again, not by re-picking.
  /// This is the exact payload B2's apply posts back.
  List<Map<String, String>> get rows =>
      List.unmodifiable([for (final row in _sheetRows) row.values]);

  /// One sentence ending in what to do next, or null.
  String? get error => _error;

  bool get isPreviewing => _isPreviewing;

  bool get isApplying => _isApplying;

  /// What the apply wrote, or null. Once it is set the fingerprint is spent: the
  /// server would call a second apply of it stale, so Apply is not offered again.
  CatalogueImportApplied? get applied => _applied;

  /// The rows the error table shows. An apply refusal replaces the preview's own
  /// errors, because it is the later word on the same rows.
  List<CatalogueImportError> get errors =>
      _applyErrors.isNotEmpty ? _applyErrors : (_preview?.errors ?? const []);

  /// The catalogue moved between the preview and the apply: the rows have to be
  /// previewed again before they can be written.
  bool get isStale => _isStale;

  /// Apply is offered only for a clean, current preview that is not mid-write
  /// and whose rows have not already been written.
  bool get canApply {
    final preview = _preview;
    if (preview == null || _isPreviewing || _isApplying) return false;
    if (_applied != null || _error != null || _applyErrors.isNotEmpty) {
      return false;
    }
    if (preview.hasErrors) return false;
    return preview.fingerprint.isNotEmpty;
  }

  /// What B2's apply must post back with [rows]; null until a preview lands.
  String? get fingerprint => _preview?.fingerprint;

  /// The spreadsheet row a preview row means. Display only: the preview numbers
  /// the rows it was SENT (1-based), while Excel counts the heading as row 1 and
  /// keeps the rows somebody emptied, which are not sent. A clerk fixing a cell
  /// needs Excel's number, so the error and change tables use this.
  int sheetRowOf(int previewRow) {
    final index = previewRow - 1;
    if (index < 0 || index >= _sheetRows.length) return previewRow;
    return _sheetRows[index].sheetRow;
  }

  /// The file could not be read off disk at all, so there is no sheet to parse:
  /// the same one banner the sheet and preview refusals use.
  void reportUnreadableFile() {
    _preview = null;
    _error = 'Could not read that file: pick the catalogue workbook again.';
    notifyListeners();
  }

  /// Reads [bytes] and asks the server what the import would do.
  ///
  /// A second call while one is running returns at once: the file picker and the
  /// Apply button both live on one wall clock, and two previews of one sheet would
  /// race for the same dialog.
  Future<void> openSheet(Uint8List bytes) async {
    if (_isPreviewing) return;
    _isPreviewing = true;
    _clearApplyState();
    notifyListeners();
    try {
      _sheetRows = parseCatalogueSheet(bytes);
    } on CatalogueImportRefusal catch (refusal) {
      _preview = null;
      _error = refusal.message;
      _isPreviewing = false;
      notifyListeners();
      return;
    }
    await _loadPreview();
  }

  /// Runs the preview again on the SAME sheet rows, which is the one fix for a
  /// stale apply: the catalogue moved, the rows did not, so nothing is re-picked.
  Future<void> previewAgain() async {
    if (_isPreviewing || _sheetRows.isEmpty) return;
    _isPreviewing = true;
    _clearApplyState();
    notifyListeners();
    await _loadPreview();
  }

  /// Writes the previewed rows, or nothing.
  ///
  /// Posts exactly what the preview answered ([rows]) plus its [fingerprint], so
  /// a catalogue that moved in between is refused rather than written against.
  /// A second press while one write is in flight, and any press after a success,
  /// send nothing: the fingerprint is spent.
  Future<void> apply() async {
    final preview = _preview;
    if (!canApply || preview == null) return;
    _isApplying = true;
    _error = null;
    _isStale = false;
    _applyErrors = const [];
    notifyListeners();
    try {
      _applied = await _service.apply(rows, preview.fingerprint);
    } on CatalogueImportServiceException catch (failure) {
      if (failure.isStale) {
        _isStale = true;
        _error = failure.message;
      } else if (failure.errors.isNotEmpty) {
        // The rows the server refused, in the table the preview already drew.
        _applyErrors = failure.errors;
      } else {
        // A refusal (a barcode taken by another writer) or no connection at all:
        // the dialog stays open and says so, and nothing claims a success.
        _error = failure.message;
      }
    } finally {
      _isApplying = false;
      notifyListeners();
    }
  }

  /// The one server call a preview makes, whether the sheet was just read or the
  /// rows are being previewed again after a stale apply.
  Future<void> _loadPreview() async {
    try {
      _preview = await _service.preview(rows);
    } on CatalogueImportServiceException catch (failure) {
      _preview = null;
      _error = failure.message;
    } finally {
      _isPreviewing = false;
      notifyListeners();
    }
  }

  /// Everything that belongs to one attempt at applying: a new sheet, or a new
  /// preview of the same rows, starts with none of it.
  void _clearApplyState() {
    _error = null;
    _isStale = false;
    _applied = null;
    _applyErrors = const [];
  }
}
