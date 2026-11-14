// Phase 3 Task F2: the import dialog's state machine.
//
// The parsed rows and the fingerprint stay on the viewmodel after a preview,
// because B2's apply posts exactly those two things back; that is why they are
// asserted here even though apply itself does not exist yet. Every way in (a
// refused workbook, a refused preview, a clean preview) is a separate state, and
// a second press while one is running must not send a second request.

import 'dart:async';
import 'dart:typed_data';

import 'package:client/data/models/catalogue_import_preview.dart';
import 'package:client/data/services/catalogue_import_service.dart';
import 'package:client/features/catalogue_io/catalogue_import_viewmodel.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers with whatever the test set, and counts the calls it was given.
class _FakeService extends CatalogueImportService {
  _FakeService();

  final List<List<Map<String, String>>> calls = [];
  CatalogueImportPreview answer = const CatalogueImportPreview(
    creates: CatalogueImportCreates(products: 1, variants: 2, units: 3),
    changes: [],
    unchanged: 4,
    errors: [],
    fingerprint: 'f1',
  );

  /// Set to make the preview fail the way the server does.
  Object? error;

  /// Held open so a test can press twice while the first call is in flight.
  Future<void>? gate;

  /// What the apply was asked, as (rows, fingerprint) pairs.
  final List<(List<Map<String, String>>, String)> applies = [];

  /// What a successful apply answers (B2).
  CatalogueImportApplied answered = const CatalogueImportApplied(
    creates: CatalogueImportCreates(products: 1, variants: 0, units: 1),
    updates: CatalogueImportCreates(products: 0, variants: 1, units: 2),
    unchanged: 3,
    summary:
        'Catalogue import applied: 1 product and 1 selling unit created; 3 '
        'rows unchanged.',
  );

  /// Set to make the apply fail the way the server does.
  Object? applyError;

  /// Held open so a test can press Apply twice while the write is in flight.
  Future<void>? applyGate;

  @override
  Future<CatalogueImportPreview> preview(List<Map<String, String>> rows) async {
    calls.add(rows);
    if (gate case final waiting?) await waiting;
    if (error case final failure?) throw failure;
    return answer;
  }

  @override
  Future<CatalogueImportApplied> apply(
    List<Map<String, String>> rows,
    String fingerprint,
  ) async {
    applies.add((rows, fingerprint));
    if (applyGate case final waiting?) await waiting;
    if (applyError case final failure?) throw failure;
    return answered;
  }
}

Uint8List goodSheet() => catalogueXlsxBytes(
  rows: const [
    CatalogueSheetRow(
      productId: 6,
      variantId: 8,
      unitId: 11,
      category: 'Electrical',
      brand: 'Omni',
      productName: 'Circuit Breaker',
      variantName: '20A 1-pole',
      unitCode: 'PC',
      unitsPerBase: 1,
      price: 315,
      barcode: 'QB000013-0',
      lowStockThreshold: 5,
      storedAt: 'Bodega',
      active: true,
    ),
  ],
  lists: CatalogueSheetLists.empty(),
);

void main() {
  late _FakeService service;
  late CatalogueImportViewmodel viewmodel;

  setUp(() {
    service = _FakeService();
    viewmodel = CatalogueImportViewmodel(service: service);
  });

  test('starts idle', () {
    expect(viewmodel.isPreviewing, isFalse);
    expect(viewmodel.preview, isNull);
    expect(viewmodel.error, isNull);
    expect(viewmodel.rows, isEmpty);
  });

  test('a sheet becomes a preview, and the rows stay for apply', () async {
    await viewmodel.openSheet(goodSheet());

    expect(viewmodel.error, isNull);
    expect(viewmodel.isPreviewing, isFalse);
    expect(viewmodel.preview?.creates.units, 3);
    expect(viewmodel.preview?.unchanged, 4);
    // Retained: B2's apply posts these rows with the fingerprint.
    expect(viewmodel.rows, hasLength(1));
    expect(viewmodel.rows.single['barcode'], 'QB000013-0');
    expect(viewmodel.fingerprint, 'f1');
    expect(service.calls.single, hasLength(1));
  });

  test('a refused workbook never reaches the server', () async {
    await viewmodel.openSheet(Uint8List.fromList([9, 9, 9]));

    expect(viewmodel.preview, isNull);
    expect(viewmodel.error, isNotNull);
    expect(service.calls, isEmpty);
  });

  test(
    'a refused preview shows the service message and keeps no preview',
    () async {
      service.error = const CatalogueImportServiceException(
        'Run the preview again',
      );

      await viewmodel.openSheet(goodSheet());

      expect(viewmodel.preview, isNull);
      expect(viewmodel.error, 'Run the preview again');
      // The rows are kept: the fix is a new preview, not another file pick.
      expect(viewmodel.rows, hasLength(1));
    },
  );

  test('a second press while one preview runs sends nothing more', () async {
    final gate = Completer<void>();
    service.gate = gate.future;

    final first = viewmodel.openSheet(goodSheet());
    final second = viewmodel.openSheet(goodSheet());
    expect(viewmodel.isPreviewing, isTrue);
    gate.complete();
    await Future.wait([first, second]);

    expect(service.calls, hasLength(1));
    expect(viewmodel.isPreviewing, isFalse);
  });

  test('a refusal clears when the next sheet is read', () async {
    await viewmodel.openSheet(Uint8List.fromList([9, 9, 9]));
    expect(viewmodel.error, isNotNull);

    await viewmodel.openSheet(goodSheet());

    expect(viewmodel.error, isNull);
    expect(viewmodel.preview, isNotNull);
  });

  // ---------------------------------------------------------------------
  // The apply (B2): the previewed rows plus its fingerprint, sent back.
  // ---------------------------------------------------------------------

  test(
    'a clean preview can be applied, and posts rows + fingerprint',
    () async {
      await viewmodel.openSheet(goodSheet());
      expect(viewmodel.canApply, isTrue);

      await viewmodel.apply();

      expect(viewmodel.applied, isNotNull);
      expect(viewmodel.applied?.creates.products, 1);
      expect(viewmodel.error, isNull);
      final (rows, fingerprint) = service.applies.single;
      expect(rows, hasLength(1));
      expect(rows.single['barcode'], 'QB000013-0');
      expect(fingerprint, 'f1');
    },
  );

  test('a second press while the apply runs sends nothing more', () async {
    await viewmodel.openSheet(goodSheet());
    final gate = Completer<void>();
    service.applyGate = gate.future;

    final first = viewmodel.apply();
    final second = viewmodel.apply();
    expect(viewmodel.isApplying, isTrue);
    expect(viewmodel.canApply, isFalse);
    gate.complete();
    await Future.wait([first, second]);

    expect(service.applies, hasLength(1));
    expect(viewmodel.isApplying, isFalse);
  });

  test('after a success a second Apply never writes again', () async {
    await viewmodel.openSheet(goodSheet());
    await viewmodel.apply();

    // The fingerprint is spent: the server would call it stale, and pressing
    // again must not even ask.
    expect(viewmodel.canApply, isFalse);
    await viewmodel.apply();
    expect(service.applies, hasLength(1));
  });

  test('a preview with row errors cannot be applied', () async {
    service.answer = const CatalogueImportPreview(
      creates: CatalogueImportCreates(products: 0, variants: 0, units: 0),
      changes: [],
      unchanged: 1,
      errors: [
        CatalogueImportError(
          row: 1,
          column: 'Price',
          code: 'INVALID_NUMBER',
          message:
              'Price "abc" is not a number: type a number, for example 12.',
        ),
      ],
      fingerprint: 'f1',
    );
    await viewmodel.openSheet(goodSheet());

    expect(viewmodel.canApply, isFalse);
    await viewmodel.apply();

    expect(service.applies, isEmpty);
    expect(viewmodel.applied, isNull);
    // The clerk's errors to fix are the preview's, in the sheet's own rows.
    expect(viewmodel.errors, hasLength(1));
  });

  test(
    'a stale apply keeps the rows and previews them again on request',
    () async {
      await viewmodel.openSheet(goodSheet());
      service.applyError = const CatalogueImportServiceException(
        CatalogueImportService.staleMessage,
        isStale: true,
      );

      await viewmodel.apply();

      expect(viewmodel.isStale, isTrue);
      expect(viewmodel.error, CatalogueImportService.staleMessage);
      expect(viewmodel.applied, isNull);
      expect(viewmodel.canApply, isFalse);
      // Still there: the fix is a new preview of THESE rows, not another pick.
      expect(viewmodel.rows, hasLength(1));

      await viewmodel.previewAgain();

      expect(service.calls, hasLength(2));
      expect(service.calls.last, viewmodel.rows);
      expect(viewmodel.isStale, isFalse);
      expect(viewmodel.error, isNull);
      expect(viewmodel.preview, isNotNull);
      // The fresh preview carries a fresh fingerprint, so Apply is offered again.
      expect(viewmodel.canApply, isTrue);
    },
  );

  test('row errors from the apply replace the ones the table shows', () async {
    await viewmodel.openSheet(goodSheet());
    service.applyError = const CatalogueImportServiceException(
      'The catalogue import was not applied: 1 row still has an error.',
      errors: [
        CatalogueImportError(
          row: 1,
          column: 'Barcode',
          code: 'BARCODE_TAKEN',
          message: 'Barcode "QB000013-0" is already on another selling unit.',
        ),
      ],
    );

    await viewmodel.apply();

    expect(viewmodel.applied, isNull);
    expect(viewmodel.isStale, isFalse);
    expect(viewmodel.errors.single.code, 'BARCODE_TAKEN');
    expect(viewmodel.canApply, isFalse);
  });

  test('a refused apply reports the refusal and claims no success', () async {
    await viewmodel.openSheet(goodSheet());
    service.applyError = const CatalogueImportServiceException(
      'Another selling unit already carries this barcode.',
    );

    await viewmodel.apply();

    expect(viewmodel.applied, isNull);
    expect(
      viewmodel.error,
      'Another selling unit already carries this barcode.',
    );
    expect(viewmodel.isApplying, isFalse);
    expect(viewmodel.canApply, isFalse);
  });
}
