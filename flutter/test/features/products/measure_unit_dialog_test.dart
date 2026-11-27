// Sell by measure (planning/sell-in-parts/2026-11-27-sell-by-measure-design.md):
// a bag sold by any number of kilos, or a roll by any length, added from the
// "Add selling unit" dialog's third tab.

import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_writes.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/products/widgets/selling_unit_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

void main() {
  repositoryRoutesMeasuredUnits();

  final cement = variant(
    id: 1,
    productId: 1,
    name: '40kg',
    baseUomId: 3,
    baseUomCode: 'BAG',
    sellingUoms: [
      variantUom(
        id: 11,
        variantId: 1,
        uomId: 3,
        uomCode: 'BAG',
        uomName: 'Bag',
        price: 260,
        isWhole: true,
      ),
    ],
  );

  const units = [
    UnitOfMeasure(id: 3, code: 'BAG', name: 'Bag', isWhole: true),
    UnitOfMeasure(id: 5, code: 'KG', name: 'Kilogram'),
    UnitOfMeasure(id: 6, code: 'M', name: 'Metre'),
    UnitOfMeasure(id: 7, code: 'PC', name: 'Piece', isWhole: true),
  ];

  Future<List<NewSellingUnit>> open(
    WidgetTester tester, {
    required ProductVariant variantUnderTest,
  }) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final submitted = <NewSellingUnit>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddSellingUnitDialog(
            productName: 'Portland Cement',
            variant: variantUnderTest,
            units: units,
            onSubmit: (unit) async {
              submitted.add(unit);
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return submitted;
  }

  testWidgets('kilos of a 40 kg bag are posted with the kilos per bag', (
    tester,
  ) async {
    final submitted = await open(tester, variantUnderTest: cement);
    await tester.tap(find.text('By weight or length'));
    await tester.pumpAndSettle();

    // Only units that can be any amount are offered.
    expect(find.byKey(const ValueKey('measure-unit-5')), findsOneWidget);
    expect(find.byKey(const ValueKey('measure-unit-7')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('measure-unit-5')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('measure-per-base')),
      '40',
    );
    await tester.enterText(find.byKey(const ValueKey('measure-price')), '7.50');
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Proportional price: ₱6.50 per KG'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('add-unit-save')));
    await tester.pumpAndSettle();

    final unit = submitted.single;
    expect(unit.measurePerBase, 40);
    expect(unit.measureUnitBody(), {
      'uom_id': 5,
      'measure_per_base': '40',
      'default_selling_price': '7.50',
    });
  });

  testWidgets('a per-bag amount of 1 or less is refused', (tester) async {
    final submitted = await open(tester, variantUnderTest: cement);
    await tester.tap(find.text('By weight or length'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('measure-unit-5')));
    await tester.enterText(find.byKey(const ValueKey('measure-per-base')), '1');
    await tester.enterText(find.byKey(const ValueKey('measure-price')), '7');
    await tester.tap(find.byKey(const ValueKey('add-unit-save')));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
    expect(find.textContaining('more than 1'), findsOneWidget);
  });

  testWidgets('an item already sold in any amount is not offered the tab', (
    tester,
  ) async {
    final loose = variant(
      id: 2,
      productId: 1,
      baseUomId: 5,
      baseUomCode: 'KG',
      baseUomIsWhole: false,
    );
    await open(tester, variantUnderTest: loose);
    await tester.tap(find.text('By weight or length'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('measure-fractional-note')),
      findsOneWidget,
    );
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('add-unit-save')),
    );
    expect(save.onPressed, isNull);
  });
}

class _RecordingService extends ProductsService {
  _RecordingService() : super();

  final calls = <(String, int, Map<String, dynamic>)>[];

  @override
  Future<void> addMeasureUnit(int variantId, Map<String, dynamic> body) async {
    calls.add(('measure', variantId, body));
  }
}

void repositoryRoutesMeasuredUnits() {
  test('the repository posts a measured unit to add-measure-unit', () async {
    final service = _RecordingService();
    await ProductsRepository(service).createSellingUnit(
      9,
      const NewSellingUnit(
        uomId: 5,
        uomCode: 'KG',
        conversionFactor: 0.025,
        sellingPrice: 7.5,
        measurePerBase: 40,
      ),
    );
    expect(service.calls.single.$1, 'measure');
    expect(service.calls.single.$2, 9);
    expect(service.calls.single.$3['measure_per_base'], '40');
  });
}
