import 'package:client/core/format/format.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sell by measure: stock of a bagged or rolled item that is also sold by the
/// kilo or the metre reads the way the store talks.
void main() {
  group('measuredStockLabel', () {
    test('bags plus kilos', () {
      expect(measuredStockLabel(9.925, 'BAG', 'KG', 40), '9 BAG + 37 KG');
      expect(measuredStockLabel(9.75, 'BAG', 'KG', 40), '9 BAG + 30 KG');
      expect(measuredStockLabel(0.31, 'BAG', 'KG', 40), '0 BAG + 12.4 KG');
    });

    test('rolls plus metres, from a 6-decimal stored amount', () {
      expect(measuredStockLabel(3.283333, 'ROLL', 'M', 150), '3 ROLL + 42.5 M');
    });

    test('a whole count reads as whole units only', () {
      expect(measuredStockLabel(10, 'BAG', 'KG', 40), '10 BAG');
      expect(measuredStockLabel(0, 'BAG', 'KG', 40), '0 BAG');
    });

    test('rounding dust below 0.01 of the unit does not show', () {
      expect(measuredStockLabel(1.000001, 'ROLL', 'M', 150), '1 ROLL');
      expect(measuredStockLabel(0.999999, 'ROLL', 'M', 150), '1 ROLL');
    });
  });

  group('formatQuantity with stored 6-decimal values', () {
    test('keeps up to three decimals and drops the noise', () {
      expect(formatQuantity(9.75), '9.75');
      expect(formatQuantity(0.075), '0.075');
      expect(formatQuantity(9.750000), '9.75');
      expect(formatQuantity(0.006667), '0.007');
    });
  });

  group('ProductVariant.measuredStockLabel', () {
    ProductVariant variant(List<VariantUom> units) => ProductVariant(
      id: 2,
      productId: 1,
      baseUomId: 3,
      minStockThreshold: 0,
      maxStockLevel: 0,
      variantName: '40kg',
      baseUomCode: 'BAG',
      isActive: true,
      sellingUoms: units,
    );
    const bag = VariantUom(
      id: 1,
      variantId: 2,
      uomId: 3,
      uomCode: 'BAG',
      uomName: 'Bag',
      barcodeQr: '',
      conversionFactor: 1,
      defaultSellingPrice: 260,
    );
    const kilo = VariantUom(
      id: 4,
      variantId: 2,
      uomId: 5,
      uomCode: 'KG',
      uomName: 'Kilogram',
      barcodeQr: '',
      conversionFactor: 0.025,
      defaultSellingPrice: 7.5,
      measurePerBase: 40,
    );

    test('a bag sold by the kilo reads bags plus kilos', () {
      expect(variant([bag, kilo]).measuredUnit, kilo);
      expect(variant([bag, kilo]).measuredStockLabel(9.75), '9 BAG + 30 KG');
    });

    test('no measured unit means no measured label', () {
      expect(variant([bag]).measuredUnit, isNull);
      expect(variant([bag]).measuredStockLabel(9.75), isNull);
    });
  });

  group('VariantUom.measurePerBase', () {
    Map<String, dynamic> body(Object? perBase) => {
      'id': 1,
      'variant': 2,
      'uom': 3,
      'uom_code': 'KG',
      'uom_name': 'Kilogram',
      'barcode_qr': '',
      'conversion_factor': '0.025',
      'default_selling_price': '7.50',
      'measure_per_base': perBase,
    };

    test('reads the kilos per bag', () {
      expect(VariantUom.fromJson(body('40.00')).measurePerBase, 40);
      expect(VariantUom.fromJson(body('40.00')).isMeasured, isTrue);
    });

    test('null or absent means an ordinary unit', () {
      expect(VariantUom.fromJson(body(null)).measurePerBase, isNull);
      expect(VariantUom.fromJson(body(null)).isMeasured, isFalse);
      final legacy = body(null)..remove('measure_per_base');
      expect(VariantUom.fromJson(legacy).measurePerBase, isNull);
    });
  });
}
