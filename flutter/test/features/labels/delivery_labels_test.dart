// Phase 6 Task 6 (decision 14): what a delivery pre-fills in the label picker.
//
// The rule the shop asked for: stickers for what actually arrived. A countable base
// unit gets one per piece received, a measured one gets a single sticker, and the
// other units of the variant are offered but start at 0.

import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/labels/delivery_labels.dart';
import 'package:client/features/labels/label_document.dart';
import 'package:flutter_test/flutter_test.dart';

VariantUom unit({
  String code = 'PC',
  String barcode = 'QB000013-0',
  double factor = 1,
  bool isWhole = true,
}) => VariantUom(
  id: 13,
  variantId: 8,
  uomId: 1,
  uomCode: code,
  uomName: code,
  barcodeQr: barcode,
  conversionFactor: factor,
  defaultSellingPrice: 10,
  uomIsWhole: isWhole,
);

List<LabelRequest> prefill(List<VariantUom> units, double received) =>
    deliveryLabelRequests(
      productName: 'Circuit Breaker',
      variantName: '20A 1-pole',
      sellingUnits: units,
      receivedQty: received,
    );

void main() {
  test('a countable base unit gets one sticker per piece received', () {
    final requests = prefill([unit()], 24);

    expect(requests.single.copies, 24);
    expect(requests.single.code, 'QB000013-0');
    expect(requests.single.unitName, 'PC');
  });

  test('a measured base unit gets exactly one sticker', () {
    final requests = prefill([
      unit(code: 'M', barcode: 'QB000020-7', isWhole: false),
    ], 18.75);

    expect(
      requests.single.copies,
      1,
      reason: '18.75 m is not 18 stickers, and 19 would lie about the roll',
    );
  });

  // Phase 1d decision 16: the SERVER owns the whole-number flag. The code word
  // is only a label, so a shop that flags `PC` as measured, or sells a
  // `QABUNDLE` in ones, must be followed rather than second-guessed.
  test('a unit coded PC but flagged measured gets one sticker', () {
    final requests = prefill([unit(isWhole: false)], 24);

    expect(
      requests.single.copies,
      1,
      reason:
          'a measured piece is not 24 countable things, whatever the code says',
    );
  });

  test(
    'a unit flagged whole gets one sticker per piece, whatever its code',
    () {
      final requests = prefill([
        unit(code: 'QABUNDLE', barcode: 'QB000060-1'),
      ], 24);

      expect(
        requests.single.copies,
        24,
        reason: 'the flag, not the word, decides what a countable unit is',
      );
    },
  );

  test('a unit that is not the base unit starts at 0', () {
    final requests = prefill([
      unit(),
      unit(code: 'BOX', barcode: 'QB000014-1', factor: 100),
    ], 24);

    expect(requests, hasLength(2));
    expect(requests.first.copies, 24);
    expect(
      requests.last.copies,
      0,
      reason: 'the box was not what arrived, so it is offered at 0 copies',
    );
  });

  test('copies are capped at the printer limit, and the cap is reported', () {
    // 2500 pieces received is one very large delivery, not 2500 stickers.
    final requests = prefill([unit()], 2500);

    expect(requests.single.copies, labelMaxCopies);
    expect(
      requests.single.cappedFrom,
      2500,
      reason:
          'the dialog has to say "Received 2500 - capped at 200", so the pre-fill '
          'must report how many were asked for before the clamp',
    );
  });

  test('a receipt under the cap reports no cap', () {
    expect(prefill([unit()], 12).single.cappedFrom, isNull);
  });

  test('a receipt of nothing asks for no stickers', () {
    expect(prefill([unit()], 0).single.copies, 0);
  });
}
