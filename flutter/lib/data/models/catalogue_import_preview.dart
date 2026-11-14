// Phase 3 Task F2: what a catalogue import preview found.
//
// The answer to `POST /api/v1/catalogue-import/preview/` (decision 23, backend
// task B1). Nothing here writes anything: the preview says what an APPLY would do,
// row by row, so the clerk can fix the sheet before a single record changes.
//
// The rows are the same ones this app sent, and [fingerprint] is the server's hash
// of them plus the records they reference. Apply (B2) posts the rows back with the
// fingerprint, so a catalogue that moved between the preview and the apply is
// refused ("Run the preview again") rather than written against.

/// What the apply DID (B2's answer to `POST .../apply/`), or, on a preview,
/// what an apply would create.
class CatalogueImportCreates {
  const CatalogueImportCreates({
    required this.products,
    required this.variants,
    required this.units,
  });

  final int products;
  final int variants;

  /// Selling units.
  final int units;

  factory CatalogueImportCreates.fromJson(Map<String, dynamic> json) =>
      CatalogueImportCreates(
        products: _int(json['products']),
        variants: _int(json['variants']),
        units: _int(json['units']),
      );
}

/// One field one row would change: `Price: 315.00 -> 320.00`.
class CatalogueImportChange {
  const CatalogueImportChange({
    required this.row,
    required this.field,
    required this.before,
    required this.after,
  });

  /// The 1-based row of the sheet the server read.
  final int row;

  /// The sheet column's heading, so the clerk knows which cell to look at.
  final String field;
  final String before;
  final String after;

  factory CatalogueImportChange.fromJson(Map<String, dynamic> json) =>
      CatalogueImportChange(
        row: _int(json['row']),
        field: _text(json['field']),
        before: _text(json['before']),
        after: _text(json['after']),
      );
}

/// One cell the server refused, worded for the clerk: it names the row, the
/// column and what to type instead.
class CatalogueImportError {
  const CatalogueImportError({
    required this.row,
    required this.column,
    required this.code,
    required this.message,
  });

  final int row;
  final String column;
  final String code;
  final String message;

  factory CatalogueImportError.fromJson(Map<String, dynamic> json) =>
      CatalogueImportError(
        row: _int(json['row']),
        column: _text(json['column']),
        code: _text(json['code']),
        message: _text(json['message']),
      );
}

/// The whole preview.
class CatalogueImportPreview {
  const CatalogueImportPreview({
    required this.creates,
    required this.changes,
    required this.unchanged,
    required this.errors,
    required this.fingerprint,
  });

  final CatalogueImportCreates creates;
  final List<CatalogueImportChange> changes;

  /// Rows that read back the way the catalogue already is.
  final int unchanged;
  final List<CatalogueImportError> errors;

  /// The server's hash of the rows and the records they reference. Empty only
  /// when the answer did not carry one, which would be a contract break: apply
  /// cannot be trusted without it.
  final String fingerprint;

  /// Apply is allowed only with zero errors (decision 23).
  bool get hasErrors => errors.isNotEmpty;

  factory CatalogueImportPreview.fromJson(Map<String, dynamic> json) {
    final creates = json['creates'];
    return CatalogueImportPreview(
      creates: CatalogueImportCreates.fromJson(
        creates is Map<String, dynamic> ? creates : const {},
      ),
      changes: [
        for (final change in _maps(json['changes']))
          CatalogueImportChange.fromJson(change),
      ],
      unchanged: _int(json['unchanged']),
      errors: [
        for (final error in _maps(json['errors']))
          CatalogueImportError.fromJson(error),
      ],
      fingerprint: _text(json['fingerprint']),
    );
  }
}

/// What one apply wrote, worded by the server.
///
/// One transaction either wrote all of this or nothing at all, so there is no
/// partial answer to read.
class CatalogueImportApplied {
  const CatalogueImportApplied({
    required this.creates,
    required this.updates,
    required this.unchanged,
    required this.summary,
  });

  final CatalogueImportCreates creates;

  /// The same three counts as [creates], under the server's `updates` key.
  final CatalogueImportCreates updates;

  /// Rows that read back the way the catalogue already was, so nothing changed.
  final int unchanged;

  /// ONE sentence for the clerk: `Catalogue import applied: 1 product created;
  /// 3 rows unchanged.` The server writes it for the audit row, so the dialog
  /// shows exactly what the audit trail keeps.
  final String summary;

  factory CatalogueImportApplied.fromJson(Map<String, dynamic> json) {
    final creates = json['creates'];
    final updates = json['updates'];
    return CatalogueImportApplied(
      creates: CatalogueImportCreates.fromJson(
        creates is Map<String, dynamic> ? creates : const {},
      ),
      updates: CatalogueImportCreates.fromJson(
        updates is Map<String, dynamic> ? updates : const {},
      ),
      unchanged: _int(json['unchanged']),
      summary: _text(json['summary']),
    );
  }
}

Iterable<Map<String, dynamic>> _maps(Object? value) => value is List
    ? value.whereType<Map<String, dynamic>>()
    : const <Map<String, dynamic>>[];

int _int(Object? value) =>
    value is int ? value : int.tryParse('${value ?? ''}') ?? 0;

String _text(Object? value) => value == null ? '' : '$value';
