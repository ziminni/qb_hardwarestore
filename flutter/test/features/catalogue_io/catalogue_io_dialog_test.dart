// Phase 3 Task F1: the export dialog and the file it hands to the platform.
//
// A widget test cannot open a Save dialog, so the exporter is behind
// [CatalogueExporter]: the assertions are about WHAT would be written. The
// cancelled-save case is tested on the real exporter with an injected
// location picker, because a cancelled dialog must be silent, not an error.

import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/catalogue_io/catalogue_io_dialog.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingExporter implements CatalogueExporter {
  final List<CatalogueSheetData> saved = [];

  /// Set to make the export fail the way an unwritable path does.
  Object? error;

  @override
  Future<void> saveXlsx(CatalogueSheetData data) async {
    final failure = error;
    if (failure != null) throw failure;
    saved.add(data);
  }
}

Product product({bool isActive = true}) => Product(
  id: 6,
  categoryId: 3,
  categoryName: 'Electrical',
  brandId: 1,
  brandName: 'Omni',
  baseName: 'Circuit Breaker',
  description: '',
  imageUrl: '',
  isActive: isActive,
  storedAtName: 'Bodega',
  variants: [
    ProductVariant(
      id: 8,
      productId: 6,
      baseUomId: 1,
      minStockThreshold: 5,
      maxStockLevel: 0,
      variantName: '20A 1-pole',
      baseUomCode: 'PC',
      isActive: true,
      sellingUoms: [
        VariantUom(
          id: 11,
          variantId: 8,
          uomId: 1,
          uomCode: 'PC',
          uomName: 'Piece',
          barcodeQr: 'QB000013-0',
          conversionFactor: 1,
          defaultSellingPrice: 315,
        ),
        VariantUom(
          id: 12,
          variantId: 8,
          uomId: 2,
          uomCode: 'BOX',
          uomName: 'Box',
          barcodeQr: 'QB000013-1',
          conversionFactor: 40,
          defaultSellingPrice: 12000,
        ),
      ],
    ),
  ],
);

CatalogueSheetLists lists() => CatalogueSheetLists.fromSources(
  categories: const [Category(id: 3, name: 'Electrical')],
  units: const [UnitOfMeasure(id: 1, code: 'PC', name: 'Piece')],
  locations: const [StorageLocation(id: 1, name: 'Bodega')],
  brands: const [Brand(id: 1, name: 'Omni')],
);

void main() {
  Future<void> pumpDialog(
    WidgetTester tester, {
    required CatalogueExporter exporter,
    List<Product>? products,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => CatalogueIoDialog(
                  products: products ?? [product()],
                  lists: lists(),
                  exporter: exporter,
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

  testWidgets('opens behind the shared AppDialog and counts the rows', (
    tester,
  ) async {
    await pumpDialog(tester, exporter: RecordingExporter());

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Export catalogue'), findsWidgets);
    // Two selling units on one product.
    expect(find.text('2 rows for 1 product'), findsOneWidget);
  });

  testWidgets('Export to Excel writes the rows and closes', (tester) async {
    final exporter = RecordingExporter();
    await pumpDialog(tester, exporter: exporter);

    await tester.tap(find.text('Save .xlsx'));
    await tester.pumpAndSettle();

    expect(exporter.saved, hasLength(1));
    final data = exporter.saved.single;
    expect(data.rows.map((row) => row.unitCode), ['PC', 'BOX']);
    expect(data.lists.categories, ['Electrical']);
    expect(find.byType(AppDialog), findsNothing);
  });

  testWidgets('a cancelled save is silent: the dialog closes, no error', (
    tester,
  ) async {
    await pumpDialog(
      tester,
      exporter: const CatalogueFileExporter(pickLocation: _cancelled),
    );

    await tester.tap(find.text('Save .xlsx'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(find.textContaining('Could not save'), findsNothing);
  });

  testWidgets('a refused save keeps the dialog open and says why', (
    tester,
  ) async {
    final exporter = RecordingExporter()..error = 'disk full';
    await pumpDialog(tester, exporter: exporter);

    await tester.tap(find.text('Save .xlsx'));
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.textContaining('Could not save the catalogue'), findsOneWidget);
  });

  testWidgets('no selling units anywhere means nothing to export', (
    tester,
  ) async {
    final exporter = RecordingExporter();
    await pumpDialog(tester, exporter: exporter, products: const <Product>[]);

    expect(find.text('0 rows for 0 products'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Save .xlsx'),
    );
    expect(button.onPressed, isNull);
  });

  group('CatalogueFileExporter', () {
    test(
      'a cancelled location picker writes nothing and does not throw',
      () async {
        await const CatalogueFileExporter(pickLocation: _cancelled).saveXlsx(
          const CatalogueSheetData(
            rows: [],
            lists: CatalogueSheetLists.empty(),
          ),
        );
      },
    );
  });
}

Future<String?> _cancelled(String suggestedName) async => null;
