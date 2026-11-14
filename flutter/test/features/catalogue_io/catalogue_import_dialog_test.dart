// Phase 3 Task F2: what the clerk sees after picking a file.
//
// Pick first, dialog second: a cancelled file pick says nothing at all, like a
// cancelled save in F1. Every state the preview can be in is drawn inside the
// shared AppDialog frame at both the narrow (760) and the wide (1100) window the
// rest of the app is checked at, because the error table is the one part of this
// dialog that has to survive being squeezed.
//
// Apply is present and DISABLED: B2 (the apply endpoint) does not exist yet, so a
// button that sent something would lie. The tooltip says when it arrives.

import 'dart:async';
import 'dart:typed_data';

import 'package:client/data/models/catalogue_import_preview.dart';
import 'package:client/data/services/catalogue_import_service.dart';
import 'package:client/features/catalogue_io/catalogue_import_dialog.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_xlsx.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalogue_import_workbook.dart';

class _FakeService extends CatalogueImportService {
  _FakeService(this.answer);

  final CatalogueImportPreview answer;
  int calls = 0;

  /// What a good apply answers, and what stops it answering.
  CatalogueImportApplied answered = const CatalogueImportApplied(
    creates: CatalogueImportCreates(products: 1, variants: 2, units: 3),
    updates: CatalogueImportCreates(products: 0, variants: 1, units: 1),
    unchanged: 7,
    summary:
        'Catalogue import applied: 1 product, 2 variants and 3 selling units '
        'created; 7 rows unchanged.',
  );
  Object? applyError;
  Future<void>? applyGate;
  int applyCalls = 0;
  final List<String> fingerprints = [];

  @override
  Future<CatalogueImportPreview> preview(List<Map<String, String>> rows) async {
    calls += 1;
    return answer;
  }

  @override
  Future<CatalogueImportApplied> apply(
    List<Map<String, String>> rows,
    String fingerprint,
  ) async {
    applyCalls += 1;
    fingerprints.add(fingerprint);
    if (applyGate case final waiting?) await waiting;
    if (applyError case final failure?) throw failure;
    return answered;
  }
}

CatalogueImportPreview cleanPreview() => const CatalogueImportPreview(
  creates: CatalogueImportCreates(products: 1, variants: 2, units: 3),
  changes: [
    CatalogueImportChange(
      row: 2,
      field: 'Price',
      before: '315.00',
      after: '320.00',
    ),
  ],
  unchanged: 7,
  errors: [],
  fingerprint: 'a1b2c3',
);

CatalogueImportPreview doubtfulPreview() => const CatalogueImportPreview(
  creates: CatalogueImportCreates(products: 0, variants: 0, units: 0),
  changes: [
    CatalogueImportChange(
      row: 2,
      field: 'Barcode',
      before: 'QB000013-0',
      after: 'QB000013-2',
    ),
  ],
  unchanged: 7,
  errors: [
    CatalogueImportError(
      row: 5,
      column: 'Category',
      code: 'UNKNOWN_CATEGORY',
      message: 'Category "Limitless" is not on the list.',
    ),
    CatalogueImportError(
      row: 9,
      column: 'Price',
      code: 'INVALID_NUMBER',
      message: 'Price "abc" is not a number: type a number, for example 12.',
    ),
  ],
  fingerprint: 'a1b2c3',
);

/// Mimics the server: it numbers the rows it was SENT, 1-based, so a row error
/// says nothing about which Excel row the clerk typed it on.
class _NumberingService extends CatalogueImportService {
  _NumberingService();

  final List<List<Map<String, String>>> calls = [];

  @override
  Future<CatalogueImportPreview> preview(List<Map<String, String>> rows) async {
    calls.add(rows);
    final errors = <CatalogueImportError>[];
    final changes = <CatalogueImportChange>[];
    for (var index = 0; index < rows.length; index++) {
      final payloadRow = index + 1;
      if (rows[index]['price'] == 'abc') {
        errors.add(
          CatalogueImportError(
            row: payloadRow,
            column: 'Price',
            code: 'INVALID_NUMBER',
            message:
                'Price "abc" is not a number: type a number, for example 12.',
          ),
        );
      }
      if (rows[index]['price'] == '400') {
        changes.add(
          CatalogueImportChange(
            row: payloadRow,
            field: 'Price',
            before: '315.00',
            after: '400.00',
          ),
        );
      }
    }
    return CatalogueImportPreview(
      creates: const CatalogueImportCreates(products: 0, variants: 0, units: 0),
      changes: changes,
      unchanged: 0,
      errors: errors,
      fingerprint: 'f1',
    );
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
  Future<void> pumpDialog(
    WidgetTester tester, {
    required Size size,
    CatalogueSheetPicker? picker,
    CatalogueImportService? service,
    Future<void> Function()? onApplied,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CatalogueImportDialog(
                  picker: picker ?? () async => goodSheet(),
                  service: service ?? _FakeService(cleanPreview()),
                  onApplied: onApplied,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder applyButton() => find.widgetWithText(FilledButton, 'Apply import');

  testWidgets('a cancelled file pick says nothing and closes', (tester) async {
    final service = _FakeService(cleanPreview());
    await pumpDialog(
      tester,
      size: const Size(1100, 900),
      picker: () async => null,
      service: service,
    );

    expect(find.byType(AppDialog), findsNothing);
    expect(service.calls, 0);
    expect(find.textContaining('Excel'), findsNothing);
  });

  testWidgets('a clean preview counts creates, changes and unchanged rows', (
    tester,
  ) async {
    await pumpDialog(tester, size: const Size(1100, 900));

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Import catalogue'), findsWidgets);
    expect(find.textContaining('1 new product'), findsOneWidget);
    expect(find.textContaining('2 new variants'), findsOneWidget);
    expect(find.textContaining('3 new selling units'), findsOneWidget);
    expect(find.textContaining('1 change'), findsOneWidget);
    expect(find.textContaining('7 rows unchanged'), findsOneWidget);
  });

  testWidgets('a change is shown before and after', (tester) async {
    await pumpDialog(tester, size: const Size(1100, 900));

    expect(find.text('Price'), findsOneWidget);
    expect(find.text('315.00'), findsOneWidget);
    expect(find.text('320.00'), findsOneWidget);
  });

  testWidgets('row errors are a table of row, column and message', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      size: const Size(1100, 900),
      service: _FakeService(doubtfulPreview()),
    );

    expect(find.byType(DataPanel<CatalogueImportError>), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
    expect(
      find.textContaining('Category "Limitless" is not on the list.'),
      findsOneWidget,
    );
    expect(find.textContaining('Price "abc" is not a number'), findsOneWidget);
    // Errors mean the file has to be fixed in Excel, so the dialog says where.
    expect(find.textContaining('Fix these cells in Excel'), findsOneWidget);
  });

  testWidgets('a clean preview can be applied', (tester) async {
    await pumpDialog(tester, size: const Size(1100, 900));

    expect(tester.widget<FilledButton>(applyButton()).onPressed, isNotNull);
  });

  testWidgets('a preview with row errors cannot be applied', (tester) async {
    await pumpDialog(
      tester,
      size: const Size(1100, 900),
      service: _FakeService(doubtfulPreview()),
    );

    expect(tester.widget<FilledButton>(applyButton()).onPressed, isNull);
  });

  testWidgets('a refused workbook is one message, not a dead dialog', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      size: const Size(1100, 900),
      picker: () async => Uint8List.fromList([1, 2, 3]),
    );

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.textContaining('not an Excel workbook'), findsOneWidget);
    // Nothing was sent, so there are no counts to show.
    expect(find.textContaining('new product'), findsNothing);
  });

  testWidgets('a refused preview shows the server message', (tester) async {
    await pumpDialog(
      tester,
      size: const Size(1100, 900),
      service: _FailingService(),
    );

    expect(find.text('Run the preview again'), findsOneWidget);
    expect(find.byType(DataPanel<CatalogueImportError>), findsNothing);
  });

  group('the row numbers a clerk edits in Excel', () {
    testWidgets('an emptied row still points at the right Excel row', (
      tester,
    ) async {
      // Sheet: row 1 headings, row 2 emptied by the clerk, row 3 fine, row 4 a
      // price that is not a number. Two rows are sent, so the server calls the
      // bad one row 2; Excel calls it row 4.
      final service = _NumberingService();
      await pumpDialog(
        tester,
        size: const Size(1100, 900),
        picker: () async => workbook(
          rows: [
            rowCells(),
            emptiedRow(),
            rowCells(productId: '8', price: 'abc'),
          ],
        ),
        service: service,
      );

      expect(service.calls.single, hasLength(2));
      expect(find.byType(DataPanel<CatalogueImportError>), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('with nothing skipped the row is the sheet row only offset by '
        'the heading', (tester) async {
      final service = _NumberingService();
      await pumpDialog(
        tester,
        size: const Size(1100, 900),
        picker: () async => workbook(
          rows: [
            rowCells(),
            rowCells(productId: '7', price: 'abc'),
          ],
        ),
        service: service,
      );

      // Sent as row 2, which is sheet row 3: the heading is row 1.
      expect(service.calls.single, hasLength(2));
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('a change row is a sheet row too', (tester) async {
      final service = _NumberingService();
      await pumpDialog(
        tester,
        size: const Size(1100, 900),
        picker: () async => workbook(
          rows: [
            rowCells(),
            emptiedRow(),
            rowCells(productId: '8', price: 400),
          ],
        ),
        service: service,
      );

      expect(service.calls.single, hasLength(2));
      expect(find.text('Price'), findsOneWidget);
      expect(find.text('400.00'), findsOneWidget);
      // Sent as row 2, but it is the fourth row of the sheet.
      expect(find.text('4'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });
  });

  testWidgets('a picker that throws says so instead of reading forever', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      size: const Size(1100, 900),
      picker: () async => throw Exception('the file went away'),
    );

    expect(find.textContaining('Reading the sheet'), findsNothing);
    expect(find.textContaining('Could not read that file'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('the apply', () {
    for (final width in const [760.0, 1100.0]) {
      testWidgets('a clean preview offers Apply at ${width.toInt()} px', (
        tester,
      ) async {
        await pumpDialog(tester, size: Size(width, 900));

        expect(applyButton(), findsOneWidget);
        expect(tester.widget<FilledButton>(applyButton()).onPressed, isNotNull);
        expect(tester.takeException(), isNull);
        // What will be written, before it is written: creates, changes, rows as
        // they are.
        expect(find.textContaining('1 new product'), findsOneWidget);
        expect(find.textContaining('1 change'), findsOneWidget);
        expect(find.textContaining('7 rows unchanged'), findsOneWidget);
      });

      testWidgets('row errors keep Apply off at ${width.toInt()} px', (
        tester,
      ) async {
        await pumpDialog(
          tester,
          size: Size(width, 900),
          service: _FakeService(doubtfulPreview()),
        );

        expect(tester.widget<FilledButton>(applyButton()).onPressed, isNull);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('applying shows progress and cannot be pressed twice', (
      tester,
    ) async {
      final service = _FakeService(cleanPreview());
      final gate = Completer<void>();
      service.applyGate = gate.future;
      await pumpDialog(tester, size: const Size(1100, 900), service: service);

      await tester.tap(applyButton());
      await tester.pump();

      final applying = find.widgetWithText(FilledButton, 'Applying');
      expect(applying, findsOneWidget);
      expect(tester.widget<FilledButton>(applying).onPressed, isNull);
      expect(
        find.descendant(
          of: applying,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      // A second press on the disabled button sends nothing.
      await tester.tap(applying, warnIfMissed: false);
      await tester.pump();
      expect(service.applyCalls, 1);

      gate.complete();
      await tester.pumpAndSettle();
      expect(service.applyCalls, 1);
    });

    testWidgets('a success says what was applied, offers Done and reloads', (
      tester,
    ) async {
      final service = _FakeService(cleanPreview());
      var reloads = 0;
      await pumpDialog(
        tester,
        size: const Size(1100, 900),
        service: service,
        onApplied: () async => reloads += 1,
      );

      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      expect(service.applyCalls, 1);
      // The fingerprint the preview answered with is what the apply sent back.
      expect(service.fingerprints.single, 'a1b2c3');
      expect(reloads, 1);
      expect(find.textContaining('Catalogue import applied'), findsWidgets);
      expect(find.textContaining('created'), findsWidgets);
      // Success is not a button that writes again: Apply is gone, Done is left.
      expect(applyButton(), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(find.byType(AppDialog), findsNothing);
      expect(service.applyCalls, 1);
      expect(reloads, 1);
    });

    testWidgets('a stale apply says so and previews the same rows again', (
      tester,
    ) async {
      final service = _FakeService(cleanPreview())
        ..applyError = const CatalogueImportServiceException(
          CatalogueImportService.staleMessage,
          isStale: true,
        );
      await pumpDialog(tester, size: const Size(1100, 900), service: service);

      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      expect(service.applyCalls, 1);
      expect(find.text(CatalogueImportService.staleMessage), findsOneWidget);
      // Nothing was written, so the dialog never says it was.
      expect(find.textContaining('Catalogue import applied'), findsNothing);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Preview again'));
      await tester.pumpAndSettle();

      // The same sheet rows, read again: no second file pick.
      expect(service.calls, 2);
      expect(find.textContaining('1 new product'), findsOneWidget);
      expect(applyButton(), findsOneWidget);
      expect(tester.widget<FilledButton>(applyButton()).onPressed, isNotNull);
    });

    testWidgets('row errors from the apply land on the Excel row', (
      tester,
    ) async {
      // Preview was clean; the catalogue moved, so the apply refuses a row. The
      // server numbers the rows it was SENT: heading, an emptied row, row 3 and
      // row 4 are sent as rows 1 and 2, and the error is about sent row 2 - which
      // Excel calls row 4.
      final service = _RowErrorAtApplyService();
      await pumpDialog(
        tester,
        size: const Size(1100, 900),
        picker: () async => workbook(
          rows: [
            rowCells(),
            emptiedRow(),
            rowCells(productId: '8'),
          ],
        ),
        service: service,
      );

      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      expect(service.applyCalls, 1);
      expect(find.byType(DataPanel<CatalogueImportError>), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('2'), findsNothing);
      expect(find.text('Barcode'), findsWidgets);
      expect(
        find.textContaining('already on another selling unit'),
        findsWidgets,
      );
      // Fix the cell first: the same file cannot be applied as it is.
      expect(tester.widget<FilledButton>(applyButton()).onPressed, isNull);
      expect(find.textContaining('Catalogue import applied'), findsNothing);
    });

    testWidgets('a barcode taken after the preview shows the server detail', (
      tester,
    ) async {
      final service = _FakeService(cleanPreview())
        ..applyError = const CatalogueImportServiceException(
          'Another selling unit already carries this barcode: choose a '
          'different code.',
        );
      await pumpDialog(tester, size: const Size(1100, 900), service: service);

      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      expect(find.byType(AppDialog), findsOneWidget);
      expect(
        find.textContaining(
          'Another selling unit already carries this barcode',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Catalogue import applied'), findsNothing);
      expect(tester.widget<FilledButton>(applyButton()).onPressed, isNull);
    });

    testWidgets('a network failure keeps the dialog open and claims nothing', (
      tester,
    ) async {
      final service = _FakeService(cleanPreview())
        ..applyError = const CatalogueImportServiceException(
          'Cannot connect to the BuildPro server.',
        );
      var reloads = 0;
      await pumpDialog(
        tester,
        size: const Size(760, 900),
        service: service,
        onApplied: () async => reloads += 1,
      );

      await tester.tap(applyButton());
      await tester.pumpAndSettle();

      expect(find.byType(AppDialog), findsOneWidget);
      expect(
        find.textContaining('Cannot connect to the BuildPro server'),
        findsOneWidget,
      );
      // No reload, no summary: the list behind the dialog is not claimed to be
      // up to date and the clerk is not told the import happened.
      expect(reloads, 0);
      expect(find.textContaining('Catalogue import applied'), findsNothing);
    });
  });

  group('at a narrow and a wide window', () {
    for (final width in const [760.0, 1100.0]) {
      testWidgets('the error table fits at ${width.toInt()} px', (
        tester,
      ) async {
        await pumpDialog(
          tester,
          size: Size(width, 900),
          service: _FakeService(doubtfulPreview()),
        );

        expect(find.byType(DataPanel<CatalogueImportError>), findsOneWidget);
        expect(applyButton(), findsOneWidget);
        // A RenderFlex overflow would already have failed the test above; this
        // pins that the rows are actually laid out, not clipped away.
        expect(tester.takeException(), isNull);
        expect(find.textContaining('new selling unit'), findsOneWidget);
      });
    }
  });
}

/// A preview that was clean, then a catalogue that moved under the apply: the
/// refusal numbers the rows it was SENT, like the server does.
class _RowErrorAtApplyService extends CatalogueImportService {
  _RowErrorAtApplyService();

  int applyCalls = 0;

  @override
  Future<CatalogueImportPreview> preview(
    List<Map<String, String>> rows,
  ) async => const CatalogueImportPreview(
    creates: CatalogueImportCreates(products: 0, variants: 0, units: 0),
    changes: [],
    unchanged: 0,
    errors: [],
    fingerprint: 'f1',
  );

  @override
  Future<CatalogueImportApplied> apply(
    List<Map<String, String>> rows,
    String fingerprint,
  ) async {
    applyCalls += 1;
    throw const CatalogueImportServiceException(
      'The catalogue import was not applied: 1 row still has an error.',
      errors: [
        CatalogueImportError(
          row: 2,
          column: 'Barcode',
          code: 'BARCODE_TAKEN',
          message: 'Barcode "QB000013-0" is already on another selling unit.',
        ),
      ],
    );
  }
}

class _FailingService extends CatalogueImportService {
  @override
  Future<CatalogueImportPreview> preview(List<Map<String, String>> rows) async {
    throw const CatalogueImportServiceException('Run the preview again');
  }
}
