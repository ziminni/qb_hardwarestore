// Phase 4 Task F2: the barcode list dialog.
//
// Two things must hold before anything is printed or downloaded: the filters
// decide exactly which codes leave the building, and only a role the server admits
// is offered the action at all. The exporter is behind [BarcodeListExporter], so
// these assertions about the payload are the same thing as assertions about the
// PDF and the CSV file.

import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/labels/barcode_list_dialog.dart';
import 'package:client/features/labels/barcode_list_document.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingExporter implements BarcodeListExporter {
  final List<BarcodeListData> csvs = [];
  final List<BarcodeListData> pdfs = [];
  final List<BarcodeListData> printed = [];

  /// Set to make every export fail the way a refused save dialog does.
  Object? error;

  void _maybeFail() {
    final failure = error;
    if (failure != null) throw failure;
  }

  @override
  Future<void> saveCsv(BarcodeListData data) async {
    _maybeFail();
    csvs.add(data);
  }

  @override
  Future<void> savePdf(BarcodeListData data) async {
    _maybeFail();
    pdfs.add(data);
  }

  @override
  Future<void> printPdf(BarcodeListData data) async {
    _maybeFail();
    printed.add(data);
  }
}

ProductVariant variant({
  required int id,
  required int productId,
  String name = '20A 1-pole',
  List<VariantUom> sellingUoms = const [],
}) => ProductVariant(
  id: id,
  productId: productId,
  baseUomId: 1,
  minStockThreshold: 5,
  maxStockLevel: 0,
  sellingUoms: sellingUoms,
  variantName: name,
  baseUomCode: 'PC',
  isActive: true,
);

VariantUom unit({
  required int id,
  required int variantId,
  String code = 'QB000013-0',
  String uomCode = 'PC',
  double price = 315,
}) => VariantUom(
  id: id,
  variantId: variantId,
  uomId: 1,
  uomCode: uomCode,
  uomName: uomCode,
  barcodeQr: code,
  conversionFactor: 1,
  defaultSellingPrice: price,
);

/// Three products: two active in different categories, one archived.
final List<Product> catalogue = [
  Product(
    id: 1,
    categoryId: 1,
    categoryName: 'Electrical',
    brandId: 1,
    brandName: 'Omni',
    baseName: 'Circuit Breaker',
    description: '',
    imageUrl: '',
    isActive: true,
    variants: [
      variant(
        id: 8,
        productId: 1,
        sellingUoms: [unit(id: 12, variantId: 8, code: 'QB000012-3')],
      ),
    ],
  ),
  Product(
    id: 2,
    categoryId: 2,
    categoryName: 'Plumbing',
    brandId: 2,
    brandName: 'Neltex',
    baseName: 'PVC Pipe',
    description: '',
    imageUrl: '',
    isActive: true,
    variants: [
      variant(
        id: 9,
        productId: 2,
        sellingUoms: [
          unit(id: 14, variantId: 9, code: 'QB000014-8', price: 95),
        ],
      ),
    ],
  ),
  Product(
    id: 3,
    categoryId: 1,
    categoryName: 'Electrical',
    brandId: 1,
    brandName: 'Omni',
    baseName: 'Retired switch',
    description: '',
    imageUrl: '',
    isActive: false,
    variants: [
      variant(
        id: 10,
        productId: 3,
        sellingUoms: [unit(id: 16, variantId: 10, code: 'QB000016-4')],
      ),
    ],
  ),
];

Future<void> pumpDialog(
  WidgetTester tester,
  RecordingExporter exporter, {
  List<Product>? products,
}) async {
  // The dialog is a full-size panel; the default 800x600 test surface is not a
  // desktop window.
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => BarcodeListDialog(
                products: products ?? catalogue,
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

void main() {
  group('role gating', () {
    // Phase 2 F3 (decision 24): the gate asks the areas the account HOLDS, so a
    // merged account keeps the action although it has no active area.
    test('Stock Manager, Store Manager and Admin may export', () {
      expect(canExportBarcodeList(const ['inventory']), isTrue);
      expect(canExportBarcodeList(const ['sales']), isTrue);
      expect(canExportBarcodeList(const ['admin']), isTrue);
      expect(canExportBarcodeList(const ['inventory', 'pos']), isTrue);
    });

    test('a cashier, an unknown code and no areas at all may not', () {
      expect(canExportBarcodeList(const ['pos']), isFalse);
      expect(canExportBarcodeList(const ['cashier']), isFalse);
      expect(canExportBarcodeList(const []), isFalse);
      expect(canExportBarcodeList(const ['pos', 'cashier']), isFalse);
    });
  });

  testWidgets('opens behind the shared AppDialog, with the count of codes', (
    tester,
  ) async {
    final exporter = RecordingExporter();
    await pumpDialog(tester, exporter);

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Barcode list'), findsWidgets);
    // Default: active products only, so the archived catalogue row is out.
    expect(find.text('2 codes from 2 products'), findsOneWidget);
  });

  testWidgets('turning "Active products only" off brings archived codes in', (
    tester,
  ) async {
    final exporter = RecordingExporter();
    await pumpDialog(tester, exporter);

    await tester.tap(find.text('Active products only'));
    await tester.pumpAndSettle();

    expect(find.text('3 codes from 3 products'), findsOneWidget);
  });

  testWidgets('the category filter narrows the list', (tester) async {
    final exporter = RecordingExporter();
    await pumpDialog(tester, exporter);

    await tester.tap(find.text('All categories'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plumbing').last);
    await tester.pumpAndSettle();

    expect(find.text('1 code from 1 product'), findsOneWidget);
  });

  testWidgets('the CSV download carries exactly the filtered rows', (
    tester,
  ) async {
    final exporter = RecordingExporter();
    await pumpDialog(tester, exporter);

    await tester.tap(find.text('Download CSV'));
    await tester.pumpAndSettle();

    expect(exporter.csvs, hasLength(1));
    final data = exporter.csvs.single;
    expect(data.rows.map((row) => row.code).toList(), [
      'QB000012-3',
      'QB000014-8',
    ]);
    expect(data.activeOnly, isTrue);
    expect(data.categoryLabel, 'All categories');
    expect(data.generatedAt, DateTime(2026, 10, 15, 10), reason: 'appClock');
    expect(exporter.pdfs, isEmpty, reason: 'CSV must not also print a PDF');
  });

  testWidgets('Print and Save PDF hand the same payload to the printer', (
    tester,
  ) async {
    final exporter = RecordingExporter();
    await pumpDialog(tester, exporter);

    await tester.tap(find.text('Save PDF'));
    await tester.pumpAndSettle();

    expect(exporter.pdfs.single.rows, hasLength(2));

    await pumpDialog(tester, exporter);
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(exporter.printed.single.rows, hasLength(2));
  });

  testWidgets('a refused export says so instead of closing the dialog', (
    tester,
  ) async {
    final exporter = RecordingExporter()..error = 'Save dialog was cancelled.';
    await pumpDialog(tester, exporter);

    await tester.tap(find.text('Download CSV'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not save the barcode list'),
      findsOneWidget,
    );
    expect(find.byType(AppDialog), findsOneWidget);
  });

  testWidgets('an empty filter result refuses to export anything', (
    tester,
  ) async {
    final exporter = RecordingExporter();
    await pumpDialog(
      tester,
      exporter,
      products: [catalogue.first.copyWith(isActive: false)],
    );

    expect(find.textContaining('No codes match these filters'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Download CSV'))
          .onPressed,
      isNull,
    );
  });
}
