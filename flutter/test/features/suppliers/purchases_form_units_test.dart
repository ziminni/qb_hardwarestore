// Phase 5 F1 (decision 18): a purchase-order line is counted in a SELLING UNIT.
//
// Pinned here by behaviour, so the wire can change shape without the screen
// silently changing meaning:
//   * the selected unit's ID is what travels (`variant_uom`) — a label is never
//     sent in its place,
//   * the default is the variant's REAL base row (`uomId == baseUomId` at factor
//     1), never "the first selling unit" — the fixture lists BAG first,
//   * a whole unit refuses 2.5 BAG while the measured KG row accepts 2.5,
//   * the cost and quantity labels name the unit, and the conversion helper is
//     written with `formatQuantity` (no floating-point artefact).

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

/// A bulk cement variant sold two ways: 1 BAG = 25 KG, and KG at factor 1.
///
/// BAG is listed FIRST on purpose: `selling_uoms` order is not identity, so a
/// screen that took the first row would count the line in bags when the base
/// unit is the kilogram.
final ProductVariant _cement = variant(
  id: 8,
  productId: 6,
  name: 'Bulk cement',
  baseUomId: 2,
  baseUomCode: 'KG',
  sellingUoms: [
    variantUom(
      id: 11,
      variantId: 8,
      uomId: 1,
      uomCode: 'BAG',
      uomName: 'Bag',
      factor: 25,
      isWhole: true,
      price: 250,
    ),
    variantUom(
      id: 12,
      variantId: 8,
      uomId: 2,
      uomCode: 'KG',
      uomName: 'Kilogram',
      price: 10,
    ),
  ],
);

Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    ('OpenSans', ['OpenSans-Regular.ttf', 'OpenSans-Bold.ttf']),
    ('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(bytes.buffer.asByteData()));
    }
    await loader.load();
  }
}

void _size(WidgetTester tester, {Size size = const Size(1400, 1000)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Opens the dialog from a button so the `PurchaseOrderFormResult` the dialog
/// pops is readable — the payload, not a guess about the payload.
class _ResultBox {
  PurchaseOrderFormResult? value;
}

Future<_ResultBox> _pumpDialog(
  WidgetTester tester, {
  Size size = const Size(1400, 1000),
  ProductVariant? prefill,
}) async {
  _size(tester, size: size);
  final box = _ResultBox();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              box.value = await showDialog<PurchaseOrderFormResult>(
                context: context,
                builder: (_) => PurchasesFormDialog(
                  suppliers: [
                    Supplier(
                      id: 9,
                      companyName: 'Cebu Steel Works',
                      contactPerson: '',
                      phone: '',
                      email: '',
                      address: '',
                      isActive: true,
                    ),
                  ],
                  products: [
                    product(
                      id: 6,
                      name: 'Portland Cement',
                      variants: [prefill ?? _cement],
                    ),
                  ],
                  costFor: (_) => 10,
                  initialVariantId: prefill?.id,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  return box;
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _chooseUnit(
  WidgetTester tester,
  int variantId,
  String code,
) async {
  await tester.tap(find.byKey(Key('po-unit-$variantId')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(code).last);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save draft'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('the default unit is the real base row, sent by id', (
    tester,
  ) async {
    final result = await _pumpDialog(tester, prefill: _cement);
    await _open(tester);

    // KG is the base row (uomId 2 at factor 1) even though BAG is listed first.
    final dropdown = tester.widget<DropdownButtonFormField<int>>(
      find.byKey(const Key('po-unit-8')),
    );
    expect(dropdown.initialValue, 12);

    await _save(tester);

    expect(result.value?.draft.toJson()['items'], [
      {'variant': 8, 'variant_uom': 12, 'ordered_qty': 1.0, 'unit_cost': 10.0},
    ]);
  });

  testWidgets('a chosen package unit is what the payload names', (
    tester,
  ) async {
    final result = await _pumpDialog(tester, prefill: _cement);
    await _open(tester);

    await _chooseUnit(tester, 8, 'BAG');
    await tester.enterText(find.byKey(const Key('po-qty-8')), '10');
    await tester.enterText(find.byKey(const Key('po-cost-8')), '250');
    await tester.pumpAndSettle();
    await _save(tester);

    expect(result.value?.draft.toJson()['items'], [
      {
        'variant': 8,
        'variant_uom': 11,
        'ordered_qty': 10.0,
        'unit_cost': 250.0,
      },
    ]);
  });

  testWidgets('labels name the unit and the helper converts in formatQuantity', (
    tester,
  ) async {
    await _pumpDialog(tester, prefill: _cement);
    await _open(tester);

    // The untouched prefill is the base unit's landed cost, so it reads per KG.
    expect(find.text('Cost per KG'), findsOneWidget);

    await _chooseUnit(tester, 8, 'BAG');
    await tester.enterText(find.byKey(const Key('po-qty-8')), '10');
    await tester.pumpAndSettle();

    expect(find.text('Cost per BAG'), findsOneWidget);
    expect(find.text('10 BAG = 250 KG'), findsOneWidget);
  });

  testWidgets('2.5 BAG is refused, 2.5 KG is accepted', (tester) async {
    final result = await _pumpDialog(tester, prefill: _cement);
    await _open(tester);

    await _chooseUnit(tester, 8, 'BAG');
    await tester.enterText(find.byKey(const Key('po-qty-8')), '2.5');
    await tester.pumpAndSettle();
    await _save(tester);

    expect(find.textContaining('Whole BAG'), findsOneWidget);
    expect(result.value, isNull, reason: 'a refused form must not pop a draft');

    await _chooseUnit(tester, 8, 'KG');
    await tester.pumpAndSettle();
    await _save(tester);

    expect(result.value?.draft.toJson()['items'], [
      {'variant': 8, 'variant_uom': 12, 'ordered_qty': 2.5, 'unit_cost': 10.0},
    ]);
  });

  testWidgets('a long unit code fits a narrow window', (tester) async {
    final long = variant(
      id: 8,
      productId: 6,
      name: 'Bulk cement',
      baseUomId: 2,
      baseUomCode: 'KG',
      sellingUoms: [
        variantUom(
          id: 14,
          variantId: 8,
          uomId: 3,
          uomCode: 'QABUNDLEWAREHOUSEPACK',
          uomName: 'Warehouse bundle pack',
          factor: 25,
          isWhole: true,
        ),
        variantUom(id: 12, variantId: 8, uomId: 2, uomCode: 'KG'),
      ],
    );
    await _pumpDialog(tester, size: const Size(760, 900), prefill: long);
    await _open(tester);

    await _chooseUnit(tester, 8, 'QABUNDLEWAREHOUSEPACK');
    await tester.enterText(find.byKey(const Key('po-qty-8')), '1000');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('1,000 QABUNDLEWAREHOUSEPACK = 25,000 KG'),
      findsOneWidget,
    );
    expect(find.text('Place order').hitTestable(), findsOneWidget);
  });
}
