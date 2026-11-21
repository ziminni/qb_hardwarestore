// A discount on ONE cart line, beside the existing whole-sale discount.
//
// The server takes the line discount off that line first and measures the sale
// discount on what is left, so the till's preview has to do the same or the
// cashier reads a total the server never charges.

import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/sale_discount.dart';
import 'package:flutter_test/flutter_test.dart';

PosCartLine line({
  double quantity = 2,
  double unitPrice = 270,
  PosDiscount? discount,
}) => PosCartLine(
  variantUomId: 1,
  productName: 'Portland Cement',
  variantName: '40kg',
  quantity: quantity,
  unit: 'BAG',
  unitPrice: unitPrice,
  availableQuantity: 100,
  discount: discount,
);

void main() {
  group('a cart line discount', () {
    test('a peso discount comes off the line total', () {
      final cement = line(
        discount: const PosDiscount(
          kind: DiscountKind.amount,
          value: 40,
          reason: 'chipped bag',
        ),
      );

      expect(cement.total, 540);
      expect(cement.discountAmount, 40);
      expect(cement.netTotal, 500);
    });

    test('a percent discount is measured on the line total', () {
      final pipe = line(
        quantity: 2,
        unitPrice: 95,
        discount: const PosDiscount(
          kind: DiscountKind.percent,
          value: 10,
          reason: 'bulk',
        ),
      );

      expect(pipe.total, 190);
      expect(pipe.discountAmount, 19);
      expect(pipe.netTotal, 171);
    });

    test('a peso discount larger than the line previews as free, not negative',
        () {
      final cement = line(
        discount: const PosDiscount(
          kind: DiscountKind.amount,
          value: 900,
          reason: 'give away',
        ),
      );

      expect(cement.discountAmount, 540);
      expect(cement.netTotal, 0);
    });

    test('a line with no discount is unchanged', () {
      expect(line().discountAmount, 0);
      expect(line().netTotal, 540);
    });
  });

  group('combined discount math (line + sale)', () {
    test('the sale discount is measured on what the line left', () {
      // 540 gross, 40 off the line, 10% off the remaining 500.
      final amounts = PosDiscountAmounts.forDiscount(
        500,
        const PosDiscount(
          kind: DiscountKind.percent,
          value: 10,
          reason: 'loyal',
        ),
        lineDiscountAmount: 40,
      );

      expect(amounts.gross, 540);
      expect(amounts.discountAmount, 50);
      expect(amounts.lineDiscountAmount, 40);
      expect(amounts.totalDiscountAmount, 90);
      expect(amounts.net, 450);
    });

    test('the approval percent is the COMBINED share of the gross', () {
      final amounts = PosDiscountAmounts.forDiscount(
        500,
        const PosDiscount(
          kind: DiscountKind.percent,
          value: 10,
          reason: 'loyal',
        ),
        lineDiscountAmount: 40,
      );

      // 90 of 540 is 16.67%, above a 10% cap even though the sale discount alone
      // is only 10%: the server measures both together.
      expect(amounts.percentOfGross, 16.67);
      expect(amounts.needsApproval(10), isTrue);
      expect(amounts.needsApproval(17), isFalse);
    });

    test('a line discount alone above the cap needs approval', () {
      // 20% off the line, no sale discount at all.
      final amounts = PosDiscountAmounts.forDiscount(
        432,
        null,
        lineDiscountAmount: 108,
      );

      expect(amounts.percentOfGross, 20);
      expect(amounts.needsApproval(10), isTrue);
    });

    // Goods the shop never discounts (cement) sit OUTSIDE the sale discount's base:
    // the server measures a percent on (gross - line discounts - never-discounted)
    // and refuses an AMOUNT bigger than that same figure.
    test('a percent is measured without the never-discounted lines', () {
      // 730 gross: 540 of cement (never discounted) + 190 of pipe.
      final amounts = PosDiscountAmounts.forDiscount(
        730,
        const PosDiscount(
          kind: DiscountKind.percent,
          value: 10,
          reason: 'loyal',
        ),
        neverDiscountedTotal: 540,
      );

      expect(amounts.discountAmount, 19);
      expect(amounts.net, 711);
      expect(amounts.gross, 730, reason: 'the customer still owes the cement');
    });

    test('an AMOUNT discount cannot exceed what may be discounted', () {
      final amounts = PosDiscountAmounts.forDiscount(
        730,
        const PosDiscount(
          kind: DiscountKind.amount,
          value: 300,
          reason: 'bulk',
        ),
        neverDiscountedTotal: 540,
      );

      expect(amounts.discountAmount, 190);
      expect(amounts.net, 540, reason: 'the cement is never given away');
    });

    test('line discounts and never-discounted lines both come off the base', () {
      // 730 gross, 5 off the pipe, 540 never discounted: 10% of 185.
      final amounts = PosDiscountAmounts.forDiscount(
        725,
        const PosDiscount(
          kind: DiscountKind.percent,
          value: 10,
          reason: 'loyal',
        ),
        lineDiscountAmount: 5,
        neverDiscountedTotal: 540,
      );

      expect(amounts.gross, 730);
      expect(amounts.discountAmount, 18.5);
      expect(amounts.percentOfGross, 3.22);
    });

    test('a cart the shop never discounts at all takes no sale discount', () {
      final amounts = PosDiscountAmounts.forDiscount(
        540,
        const PosDiscount(
          kind: DiscountKind.percent,
          value: 10,
          reason: 'loyal',
        ),
        neverDiscountedTotal: 540,
      );

      expect(amounts.discountAmount, 0);
      expect(amounts.net, 540);
    });

    test('no line discount leaves the old arithmetic alone', () {
      final amounts = PosDiscountAmounts.forDiscount(
        1000,
        const PosDiscount(
          kind: DiscountKind.amount,
          value: 100,
          reason: 'bulk',
        ),
      );

      expect(amounts.gross, 1000);
      expect(amounts.net, 900);
      expect(amounts.percentOfGross, 10);
      expect(amounts.needsApproval(10), isFalse);
    });
  });
}
