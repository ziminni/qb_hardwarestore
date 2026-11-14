// Phase 9 F2 (decision 21 §2): the driver is told the SPLIT - "Pick up: 3 BAG at
// Store, 2 BAG at Bodega" - because a trip that starts at one shelf is a wasted
// trip. A slip whose sale predates Phase 9 keeps the Phase 5 caption.

import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/pick_up.dart';
import 'package:client/features/deliveries/widgets/delivery_slip_document.dart';
import 'package:flutter_test/flutter_test.dart';

Delivery _delivery(List<DeliveryItem> items) => Delivery(
  id: 1,
  deliveryNo: 'DLV-20261114-0001',
  saleId: 9,
  salesOrderId: null,
  transactionNo: 'TRX-20261114-0009',
  orderNo: '',
  customerId: 3,
  customerName: 'Maria Santos',
  address: '12 Mabini St, Cebu City',
  contactName: 'Maria Santos',
  contactPhone: '09171234567',
  scheduledDate: DateTime(2026, 11, 15),
  fee: 50,
  status: DeliveryStatus.scheduled,
  failureReason: '',
  items: items,
  createdByName: 'Maria Santos',
  createdAt: DateTime(2026, 11, 14, 9),
);

void main() {
  test('a line picked from two shelves names both', () {
    final content = DeliverySlipContent(
      _delivery(const [
        DeliveryItem(
          name: 'Portland cement',
          unit: 'BAG',
          qty: 5,
          storedAtName: 'Bodega',
          pickUp: [
            PickUpPart(
              locationId: 1,
              locationName: 'Store',
              qty: 3,
              unit: 'BAG',
            ),
            PickUpPart(
              locationId: 2,
              locationName: 'Bodega',
              qty: 2,
              unit: 'BAG',
            ),
          ],
        ),
      ]),
    );

    expect(
      content.lines.single.pickUpLine,
      'Pick up: 3 BAG at Store, 2 BAG at Bodega',
    );
  });

  test('a line with no pick_up keeps the Phase 5 caption', () {
    final content = DeliverySlipContent(
      _delivery(const [
        DeliveryItem(
          name: 'Portland cement',
          unit: 'BAG',
          qty: 5,
          storedAtName: 'Bodega',
        ),
      ]),
    );

    expect(content.lines.single.pickUpLine, 'Pick up at Bodega');
  });
}
