// Phase 1b (decisions 09, 10, 13 and 14): the request read-back carries what the store
// decided, why, and a NON-DEBT expected amount that may be unknown.
//
// Three things this file pins, because getting any of them wrong costs money or trust:
//
//   * `expected_amount` is a 2dp string or null, and NULL MEANS UNKNOWN. Never 0.
//   * `available` is store intent: true / false / null (not answered yet). Null is not
//     false, and a non-bool is a contract break rather than a silent guess.
//   * the CPMS approver and the request notes are shown as CPMS wrote them; the POS
//     reviewer never replaces the approver's name.
import 'package:client/data/models/requisition.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _line({
  int id = 21,
  Object? available = _absent,
  String declineReason = '',
  String productName = 'Portland Cement',
  String unit = '40 kg bag',
}) => {
  'id': id,
  'requisition': 7,
  'variant_uom': 12,
  'variant': 4,
  'variant_name': '40 kg',
  'product_name': productName,
  'unit': unit,
  'quantity': '4.00',
  'released_qty': '0.00',
  'notes': '',
  if (!identical(available, _absent)) 'available': available,
  'decline_reason': declineReason,
};

/// Marks an argument as "leave the key out entirely" — an older server's answer.
const Object _absent = Object();

Map<String, dynamic> _row({
  int id = 7,
  String status = 'ACCEPTED',
  String cpmsRequestId = 'CPMS-REQ-8842',
  String? approverName = 'Engr. Reyes',
  String notes = 'Deliver to gate 2 before noon.',
  String declineReason = '',
  Object? expectedAmount = '1260.00',
  List<Map<String, dynamic>>? items,
}) => {
  'id': id,
  'project': 1,
  'project_name': '2-Storey House - Mandaue',
  'project_customer_name': 'Dela Cruz Construction',
  'req_number': 'REQ-20261107-0007',
  'requested_by': 5,
  'requested_by_name': 'Fore Man',
  'approver_name': approverName,
  'cpms_request_id': cpmsRequestId,
  'status': status,
  'notes': notes,
  'decline_reason': declineReason,
  'expected_amount': ?expectedAmount,
  'items': items ?? [_line()],
  'token': null,
  'created_at': '2026-11-07T08:15:00+08:00',
  'updated_at': '2026-11-07T09:00:00+08:00',
};

void main() {
  group('Requisition: the CPMS context the queue has to show', () {
    test('decodes the CPMS request id, approver, notes and received date', () {
      final req = Requisition.fromJson(_row());

      expect(req.cpmsRequestId, 'CPMS-REQ-8842');
      expect(
        req.approverName,
        'Engr. Reyes',
        reason:
            'the CPMS approver answers the project, so it is shown as they were',
      );
      expect(req.notes, 'Deliver to gate 2 before noon.');
      expect(req.createdAt, DateTime.parse('2026-11-07T08:15:00+08:00'));
      expect(req.status, RequisitionStatus.accepted);
    });

    test('a request with no approver or notes yet still reads', () {
      // WAITING rows have no approver and often no notes: a null is a fact, not a break.
      final req = Requisition.fromJson(
        _row(status: 'WAITING', approverName: null, notes: ''),
      );

      expect(req.approverName, isNull);
      expect(req.notes, '');
      expect(req.status, RequisitionStatus.waiting);
    });

    test('a whole Decline carries its reason', () {
      final req = Requisition.fromJson(
        _row(status: 'DECLINED', declineReason: 'Cannot supply this request'),
      );

      expect(req.status, RequisitionStatus.declined);
      expect(req.declineReason, 'Cannot supply this request');
    });

    test(
      'a missing cpms id and a missing created_at do not break the decode',
      () {
        final json = _row()
          ..remove('cpms_request_id')
          ..remove('created_at');
        final req = Requisition.fromJson(json);

        expect(req.cpmsRequestId, isNull);
        expect(req.createdAt, isNull);
      },
    );
  });

  // Decision 14: a historical request whose released total was never recorded keeps an
  // UNKNOWN amount. ₱0.00 would tell the project the store released nothing, which the
  // POS cannot know. Zero and unknown must stay distinguishable everywhere.
  group('Requisition: expected amount, where null is not zero', () {
    test('a null amount stays null', () {
      final req = Requisition.fromJson(_row(expectedAmount: null));

      expect(req.expectedAmount, isNull);
    });

    test('an absent amount stays null', () {
      final json = _row()..remove('expected_amount');

      expect(Requisition.fromJson(json).expectedAmount, isNull);
    });

    test('a zero amount is a real zero, not an unknown', () {
      final req = Requisition.fromJson(_row(expectedAmount: '0.00'));

      expect(req.expectedAmount, 0);
      expect(req.expectedAmount, isNotNull);
    });

    test('a genuine amount reads as its 2dp value', () {
      expect(
        Requisition.fromJson(_row(expectedAmount: '1260.50')).expectedAmount,
        1260.5,
      );
    });

    test('a non-numeric amount is a contract break', () {
      expect(
        () => Requisition.fromJson(_row(expectedAmount: 'about a thousand')),
        throwsFormatException,
      );
    });
  });

  group('RequisitionItem: Available / Not available', () {
    test('an accepted line is available with no reason', () {
      final line = Requisition.fromJson(
        _row(items: [_line(available: true)]),
      ).items.single;

      expect(line.available, isTrue);
      expect(line.declineReason, '');
    });

    test('a Not available line carries the reason the store gave', () {
      final line = Requisition.fromJson(
        _row(
          items: [
            _line(
              available: false,
              declineReason: 'We do not carry 16 mm rebar',
            ),
          ],
        ),
      ).items.single;

      expect(line.available, isFalse);
      expect(line.declineReason, 'We do not carry 16 mm rebar');
    });

    test('an unanswered line reads null, never false', () {
      final line = Requisition.fromJson(_row()).items.single;

      expect(
        line.available,
        isNull,
        reason:
            'a WAITING line has no decision yet; false would mean the store said no',
      );
      expect(line.declineReason, '');
    });

    test('the product and selling unit ride along for the queue label', () {
      final line = Requisition.fromJson(_row()).items.single;

      expect(line.productName, 'Portland Cement');
      expect(line.unit, '40 kg bag');
      expect(line.variantName, '40 kg');
    });

    test('a product label the server omits reads as blank, not as a crash', () {
      final json = _line()
        ..remove('product_name')
        ..remove('unit');
      final line = Requisition.fromJson(_row(items: [json])).items.single;

      expect(line.productName, '');
      expect(line.unit, '');
    });

    test('an available flag that is not a bool is a contract break', () {
      // A string "false" would read as TRUE in a naive cast, and the till would offer a
      // line the store declined. Failing loudly is the only safe answer.
      for (final wrong in <Object>['true', 'false', 1, 0]) {
        expect(
          () => Requisition.fromJson(_row(items: [_line(available: wrong)])),
          throwsFormatException,
          reason: 'available=$wrong must not be guessed',
        );
      }
    });
  });
}
