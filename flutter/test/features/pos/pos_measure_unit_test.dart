// Sell by measure: a kilo card of a 40 kg bag, or a metre card of a 150 m
// roll. The till reads what is left by MULTIPLYING the bags by the kilos per
// bag; dividing by the rounded factor (0.006667 for a metre) would show a
// 150 m roll as 149.99 m.

import 'package:client/data/models/pos_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

PosCatalogItem _item({
  required String unit,
  required double factor,
  required double baseStock,
  double? measurePerBase,
}) => PosCatalogItem(
  variantUomId: 1,
  variantId: 1,
  productName: 'THHN Wire',
  variantName: '2.0mm',
  unit: unit,
  barcode: '',
  conversionFactor: factor,
  unitPrice: 12,
  availableBaseStock: baseStock,
  measurePerBase: measurePerBase,
);

void main() {
  test('a metre card reads the exact metres left on the rolls', () {
    final metre = _item(
      unit: 'M',
      factor: 0.006667,
      baseStock: 1,
      measurePerBase: 150,
    );
    expect(metre.availableSaleQuantity, 150);
    expect(metre.isMeasured, isTrue);
  });

  test('a kilo card reads 9.75 bags as 390 kg', () {
    final kilo = _item(
      unit: 'KG',
      factor: 0.025,
      baseStock: 9.75,
      measurePerBase: 40,
    );
    expect(kilo.availableSaleQuantity, 390);
  });

  test('an ordinary unit still divides by its factor', () {
    final box = _item(unit: 'BOX', factor: 12, baseStock: 36);
    expect(box.availableSaleQuantity, 3);
    expect(box.isMeasured, isFalse);
  });
}
