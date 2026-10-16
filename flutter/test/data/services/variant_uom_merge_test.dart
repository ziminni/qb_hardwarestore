// The product form edits ONE selling unit (the base one). Rebuilding the whole
// list from form input would silently delete any additional unit the variant
// had — harmless while the mock carries one unit per variant, but real API data
// can carry several, and then an edit would destroy them.

import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/services/variant_uom_merge.dart';
import 'package:flutter_test/flutter_test.dart';

VariantUom _uom({
  required int id,
  required String code,
  required String barcode,
  required double price,
  double factor = 1,
}) => VariantUom(
  id: id,
  variantId: 7,
  uomId: id,
  uomCode: code,
  uomName: code,
  barcodeQr: barcode,
  conversionFactor: factor,
  defaultSellingPrice: price,
);

void main() {
  group('mergePrimarySellingUom', () {
    test('creates the primary unit when the variant has none', () {
      final merged = mergePrimarySellingUom(
        existing: const [],
        variantId: 7,
        uomCode: 'Bag',
        barcodeQr: 'QB-1',
        defaultSellingPrice: 315,
      );

      expect(merged, hasLength(1));
      expect(merged.single.uomCode, 'Bag');
      expect(merged.single.barcodeQr, 'QB-1');
      expect(merged.single.defaultSellingPrice, 315.0);
      expect(merged.single.variantId, 7);
    });

    test('replaces the primary unit in place, keeping its id', () {
      final merged = mergePrimarySellingUom(
        existing: [_uom(id: 42, code: 'PC', barcode: 'old', price: 10)],
        variantId: 7,
        uomCode: 'PC',
        barcodeQr: 'new',
        defaultSellingPrice: 20,
      );

      expect(merged, hasLength(1));
      expect(merged.single.id, 42); // the row identity survives the edit
      expect(merged.single.barcodeQr, 'new');
      expect(merged.single.defaultSellingPrice, 20.0);
    });

    test('PRESERVES additional selling units beyond the primary', () {
      // The defect this guards: an edit that rebuilt the list from the form
      // would drop the Box and Pallet units entirely.
      final merged = mergePrimarySellingUom(
        existing: [
          _uom(id: 1, code: 'PC', barcode: 'pc-code', price: 10),
          _uom(id: 2, code: 'Box', barcode: 'box-code', price: 100, factor: 12),
          _uom(
            id: 3,
            code: 'Pallet',
            barcode: 'pallet-code',
            price: 1000,
            factor: 144,
          ),
        ],
        variantId: 7,
        uomCode: 'PC',
        barcodeQr: 'pc-code-v2',
        defaultSellingPrice: 12,
      );

      expect(merged, hasLength(3));
      expect(merged.map((u) => u.uomCode), ['PC', 'Box', 'Pallet']);
      expect(merged.first.defaultSellingPrice, 12.0);
      // The untouched units keep their own price and conversion.
      expect(merged[1].defaultSellingPrice, 100.0);
      expect(merged[1].conversionFactor, 12.0);
      expect(merged[2].conversionFactor, 144.0);
    });
  });
}
