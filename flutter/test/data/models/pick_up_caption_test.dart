// Phase 9 F2 (decision 21 §2 and §4): a line is no longer picked up from ONE
// place. The server says which shelf each part left - "3 at Store, 2 at Bodega" -
// and every surface that prints a pick-up point reads that same list through one
// caption, so the receipt, the slip and the release cannot word it differently.
//
// The old wire has no `pick_up` at all: such a row keeps the caption Phase 5
// printed ("Pick up at Bodega"), and a row with neither prints nothing rather
// than inventing a place.

import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/pick_up.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the caption', () {
    test('names every shelf the line left, in the order it was picked', () {
      expect(
        pickUpCaption(
          pickUp: const [
            PickUpPart(
              locationId: 1,
              locationName: 'Store',
              qty: 3,
              unit: 'PC',
            ),
            PickUpPart(
              locationId: 2,
              locationName: 'Bodega',
              qty: 2,
              unit: 'PC',
            ),
          ],
          storedAtName: 'Bodega',
        ),
        'Pick up: 3 PC at Store, 2 PC at Bodega',
      );
    });

    test('one shelf still reads as a pick-up point', () {
      expect(
        pickUpCaption(
          pickUp: const [
            PickUpPart(locationId: 1, locationName: 'Store', qty: 5, unit: 'BAG'),
          ],
          storedAtName: '',
        ),
        'Pick up: 5 BAG at Store',
      );
    });

    test('an old wire with no pick_up keeps the Phase 5 caption', () {
      expect(
        pickUpCaption(pickUp: const [], storedAtName: 'Bodega'),
        'Pick up at Bodega',
      );
    });

    test('neither a split nor a name prints nothing', () {
      expect(pickUpCaption(pickUp: const [], storedAtName: '   '), isNull);
    });

    test('a split in base units keeps the decimals it needs', () {
      expect(
        pickUpCaption(
          pickUp: const [
            PickUpPart(locationId: 1, locationName: 'Store', qty: 7, unit: 'PC'),
            PickUpPart(
              locationId: 2,
              locationName: 'Bodega',
              qty: 2.5,
              unit: 'KG',
            ),
          ],
          storedAtName: '',
        ),
        'Pick up: 7 PC at Store, 2.5 KG at Bodega',
      );
    });
  });

  group('the wire', () {
    test('a sale line decodes its pick_up list', () {
      final line = TransactionLineItem.fromJson({
        'variant_uom': 4,
        'variant_uom_code': 'BAG',
        'qty': '5.00',
        'unit_price': '270.00',
        'subtotal': '1350.00',
        'stored_at_name': 'Bodega',
        'pick_up': [
          {
            'location': 1,
            'location_name': 'Store',
            'qty': '3.00',
            'unit': 'BAG',
          },
          {
            'location': 2,
            'location_name': 'Bodega',
            'qty': '2.00',
            'unit': 'BAG',
          },
        ],
      });

      expect(line.pickUp, hasLength(2));
      expect(line.pickUp.first.locationName, 'Store');
      expect(line.pickUp.first.qty, 3);
      expect(
        pickUpCaption(pickUp: line.pickUp, storedAtName: line.storedAtName),
        'Pick up: 3 BAG at Store, 2 BAG at Bodega',
      );
    });

    test('a sale line from a pre-Phase-9 server decodes to no parts', () {
      final line = TransactionLineItem.fromJson({
        'variant_uom': 4,
        'variant_uom_code': 'BAG',
        'qty': '5.00',
        'unit_price': '270.00',
        'subtotal': '1350.00',
        'stored_at_name': 'Bodega',
      });

      expect(line.pickUp, isEmpty);
      expect(
        pickUpCaption(pickUp: line.pickUp, storedAtName: line.storedAtName),
        'Pick up at Bodega',
      );
    });

    test('a delivery item decodes its pick_up list', () {
      final item = DeliveryItem.fromJson({
        'name': 'Portland cement',
        'unit': 'BAG',
        'qty': '5.00',
        'stored_at_name': 'Bodega',
        'pick_up': [
          {
            'location': 1,
            'location_name': 'Store',
            'qty': '3.00',
            'unit': 'BAG',
          },
        ],
      });

      expect(item.pickUp, hasLength(1));
      expect(item.pickUp.single.locationId, 1);
    });
  });
}
