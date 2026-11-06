// Phase 1, Task 9 (decision 05): release what the shelf holds and leave the rest open on
// the same token. That makes the token check carry per line WHAT CAN LEAVE NOW, and the
// release answer carry what this scan moved and what is still owed.
//
// Read from backend_django/apps/requisitions/services.py (`verify_token`,
// `_availability`, `release_materials`), never guessed: `availability` is one of
// FULL / SHORT / UNAVAILABLE / DONE, and the release answer is
// {status, items: [{code, released_now, outstanding}]}.
import 'package:client/data/models/requisition.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _line({
  int id = 1,
  String quantity = '10.00',
  String remaining = '10.00',
  String availability = 'FULL',
  String releasable = '10.00',
}) => {
  'id': id,
  'variant_id': 7,
  'variant_name': 'Portland Cement 40 kg',
  'quantity': quantity,
  'remaining': remaining,
  'availability': availability,
  'releasable': releasable,
};

Map<String, dynamic> _verify(List<Map<String, dynamic>> items) => {
  'token': 'd5a4eb1f-0e88-497d-bc3b-688b14a6a867',
  'requisition': {
    'id': 3,
    'req_number': 'REQ-20260925-0003',
    'project': '2-Storey House - Mandaue',
    'customer': 'Dela Cruz Construction',
  },
  'items': items,
};

Map<String, dynamic> _release({
  String status = 'RELEASED',
  List<Map<String, dynamic>>? items,
}) => {
  'transaction_id': 14,
  'transaction_no': 'TRX-20261017-0001',
  'req_number': 'REQ-20260925-0003',
  'status': status,
  'items':
      items ??
      [
        {'code': 'CEM-40', 'released_now': '10.00', 'outstanding': '0.00'},
      ],
  'grand_total': '1260.00',
  'ledger_id': 4,
  'balance_due': '1260.00',
};

void main() {
  group('TokenVerification: what can leave the store now', () {
    test('reads each line as full, short, unavailable or already released', () {
      final verified = TokenVerification.fromJson(
        _verify([
          _line(),
          _line(
            id: 2,
            quantity: '10.00',
            remaining: '10.00',
            availability: 'SHORT',
            releasable: '4.00',
          ),
          _line(id: 3, availability: 'UNAVAILABLE', releasable: '0.00'),
          _line(
            id: 4,
            quantity: '24.00',
            remaining: '0.00',
            availability: 'DONE',
            releasable: '0.00',
          ),
        ]),
      );

      expect(verified.items.map((item) => item.availability), [
        LineAvailability.full,
        LineAvailability.short,
        LineAvailability.unavailable,
        LineAvailability.done,
      ]);
    });

    test('a short line says how much goes now and how much stays open', () {
      final short = TokenVerification.fromJson(
        _verify([
          _line(
            quantity: '10.00',
            remaining: '10.00',
            availability: 'SHORT',
            releasable: '4.00',
          ),
        ]),
      ).items.single;

      expect(short.goesNow, 4);
      expect(
        short.outstanding,
        6,
        reason: 'the rest stays open on this token for the next visit',
      );
      expect(short.isReleasable, isTrue);
    });

    test(
      'a full line leaves nothing open and a done line is not releasable',
      () {
        final verified = TokenVerification.fromJson(
          _verify([
            _line(),
            _line(
              id: 2,
              quantity: '24.00',
              remaining: '0.00',
              availability: 'DONE',
              releasable: '0.00',
            ),
          ]),
        );

        expect(verified.items.first.outstanding, 0);
        expect(verified.items.first.isReleasable, isTrue);
        expect(
          verified.items.last.isReleasable,
          isFalse,
          reason: 'an earlier scan already took that line, so a second cannot',
        );
        expect(verified.items.last.outstanding, 0);
      },
    );

    test(
      'an availability word this client was never taught reads as unavailable',
      () {
        // The one error a release cannot undo is promising stock that is not there, so a
        // new server word must be read as "nothing can go", never as FULL and never as a
        // crash on the only irreversible screen.
        final line = TokenVerification.fromJson(
          _verify([_line(availability: 'BACKORDERED', releasable: '10.00')]),
        ).items.single;

        expect(line.availability, LineAvailability.unavailable);
        expect(line.isReleasable, isFalse);
        expect(line.goesNow, 0);
        expect(
          line.outstanding,
          10,
          reason: 'the whole line stays open when nothing leaves the store',
        );
      },
    );

    test(
      'a line without the availability fields reads as nothing releasable',
      () {
        final line = TokenVerification.fromJson({
          'token': 'a-token',
          'requisition': {
            'id': 3,
            'req_number': 'REQ-1',
            'project': 'P',
            'customer': 'C',
          },
          'items': [
            {
              'id': 31,
              'variant_id': 4,
              'variant_name': '1/2 inch x 3m',
              'quantity': '4.00',
              'remaining': '4.00',
            },
          ],
        }).items.single;

        expect(line.availability, LineAvailability.unavailable);
        expect(line.releasable, 0);
        expect(line.isReleasable, isFalse);
      },
    );
  });

  group('ReleaseResult: what this scan moved and what stays open', () {
    test('a partial release says so and counts the lines still open', () {
      final result = ReleaseResult.fromJson(
        _release(
          status: 'PARTIAL',
          items: [
            {'code': 'CEM-40', 'released_now': '10.00', 'outstanding': '0.00'},
            {'code': 'STL-10', 'released_now': '4.00', 'outstanding': '6.00'},
            {'code': 'PLY-34', 'released_now': '0.00', 'outstanding': '12.00'},
          ],
        ),
      );

      expect(result.status, ReleaseStatus.partial);
      expect(result.isPartial, isTrue);
      expect(result.openLineCount, 2);
      expect(result.items[1].releasedNow, 4);
      expect(result.items[1].outstanding, 6);
    });

    test('a full release leaves no line open', () {
      final result = ReleaseResult.fromJson(_release());

      expect(result.status, ReleaseStatus.released);
      expect(result.isPartial, isFalse);
      expect(result.openLineCount, 0);
    });

    test('open lines make the answer partial even when the status word is new', () {
      // The status is read off the WIRE, so a status this build has not been taught
      // must not tell a clerk the request is finished while a line still owes goods.
      final result = ReleaseResult.fromJson(
        _release(
          status: 'SOMETHING_NEW',
          items: [
            {'code': 'STL-10', 'released_now': '4.00', 'outstanding': '6.00'},
          ],
        ),
      );

      expect(result.status, ReleaseStatus.unknown);
      expect(result.isPartial, isTrue);
      expect(result.openLineCount, 1);
    });
  });
}
