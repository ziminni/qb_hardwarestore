// Phase 5 F3 (decision 18): the delivery slip on paper.
//
// The slip is the driver's document, so what it says must be checked without a
// printer: the items and their selling quantities, the pick-up point when the
// server names one (B4 "Stored at"), the contact and address, the date and the
// delivery charge. The bundled font has no peso glyph, so paper spells the
// currency `PHP`.

import 'package:client/data/models/delivery.dart';
import 'package:client/features/deliveries/widgets/delivery_slip_document.dart';
import 'package:flutter_test/flutter_test.dart';

Delivery _delivery({
  double fee = 50,
  DeliveryStatus status = DeliveryStatus.scheduled,
  String failureReason = '',
  List<DeliveryItem> items = const [
    DeliveryItem(name: 'Portland cement', unit: 'BAG', qty: 2),
  ],
}) => Delivery(
  id: 1,
  deliveryNo: 'DLV-20261111-0001',
  saleId: 9,
  salesOrderId: null,
  transactionNo: 'TRX-20261111-0009',
  orderNo: '',
  customerId: 3,
  customerName: 'Maria Santos',
  address: '12 Mabini St, Cebu City',
  contactName: 'Maria Santos',
  contactPhone: '09171234567',
  scheduledDate: DateTime(2026, 11, 12),
  fee: fee,
  status: status,
  failureReason: failureReason,
  items: items,
  createdByName: 'Maria Santos',
  createdAt: DateTime(2026, 11, 11, 9),
);

void main() {
  test('a slip names the document, the trip, the contact and the address', () {
    final content = DeliverySlipContent(_delivery());

    expect(content.header, contains('Delivery slip: DLV-20261111-0001'));
    expect(content.header, contains('Sale TRX-20261111-0009'));
    expect(content.header, contains('Scheduled: Nov 12, 2026'));
    expect(content.header, contains('Contact: Maria Santos'));
    expect(content.header, contains('Phone: 09171234567'));
    expect(content.header, contains('Address: 12 Mabini St, Cebu City'));
  });

  test('items print the name, quantity and unit, with no pick-up line when '
      'stored_at_name is absent', () {
    final content = DeliverySlipContent(
      _delivery(
        items: const [
          DeliveryItem(name: 'Portland cement', unit: 'BAG', qty: 2),
          DeliveryItem(name: 'Sand', unit: 'CU.M', qty: 1.5),
        ],
      ),
    );

    expect(content.lines, hasLength(2));
    expect(content.lines.first.name, 'Portland cement');
    expect(content.lines.first.quantityLine, '2 BAG');
    expect(content.lines.last.quantityLine, '1.5 CU.M');
    expect(
      content.lines.first.pickUpLine,
      isNull,
      reason: 'an absent stored_at_name must print no pick-up line at all',
    );
  });

  test('stored_at_name becomes the pick-up point (B4)', () {
    final content = DeliverySlipContent(
      _delivery(
        items: const [
          DeliveryItem(
            name: 'Portland cement',
            unit: 'BAG',
            qty: 2,
            storedAtName: 'Bodega',
          ),
        ],
      ),
    );

    expect(content.lines.single.pickUpLine, 'Pick up at Bodega');
  });

  test(
    'the delivery charge prints in paper pesos, and a zero fee prints nothing',
    () {
      final charged = DeliverySlipContent(_delivery(fee: 50));
      expect(charged.feeLine, ('Delivery charge', 'PHP 50.00'));

      final free = DeliverySlipContent(_delivery(fee: 0));
      expect(
        free.feeLine,
        isNull,
        reason: 'a 0.00 charge line reads as a charge that was made',
      );
    },
  );

  test('a failed slip carries the reason; a live one carries none', () {
    final failed = DeliverySlipContent(
      _delivery(
        status: DeliveryStatus.failed,
        failureReason: 'Customer not home.',
      ),
    );
    expect(failed.failureReason, 'Customer not home.');
    expect(DeliverySlipContent(_delivery()).failureReason, isEmpty);
  });

  test('no peso glyph reaches the paper: the bundled font lacks it', () {
    final content = DeliverySlipContent(
      _delivery(
        items: const [
          DeliveryItem(
            name: 'Portland cement',
            unit: 'BAG',
            qty: 2,
            storedAtName: 'Bodega',
          ),
        ],
      ),
    );
    final printed = [
      ...content.header,
      for (final line in content.lines) ...[
        line.name,
        line.quantityLine,
        ?line.pickUpLine,
      ],
      if (content.feeLine case (final label, final amount)) ...[label, amount],
    ];
    for (final text in printed) {
      expect(
        text,
        isNot(contains('₱')),
        reason: '"$text" would print as a box',
      );
    }
  });

  test('the slip renders as an 80 mm document', () async {
    final pdf = await buildDeliverySlipPdf(_delivery());
    expect(pdf, isNotEmpty);
  });
}
