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
  Object? available = _absent,
  String? declineReason,
}) => {
  'id': id,
  'variant_id': 7,
  'variant_name': 'Portland Cement 40 kg',
  'quantity': quantity,
  'remaining': remaining,
  'availability': availability,
  'releasable': releasable,
  if (!identical(available, _absent)) 'available': available,
  'decline_reason': ?declineReason,
};

/// Marks an argument as "leave the key out entirely" — an older server's answer.
const Object _absent = Object();

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

  // Phase 1b (decision 10): the STORE's answer per line rides on the same wire as the
  // shelf check. "Not available" (the store declined the line) is not "Unavailable"
  // (the shelf is empty today), so the client decodes both separately.
  group('TokenVerification: the store decision on each line', () {
    test('a line the store marked Not available carries its reason', () {
      final line = TokenVerification.fromJson(
        _verify([
          _line(available: false, declineReason: 'We do not carry 16 mm rebar'),
        ]),
      ).items.single;

      expect(line.available, isFalse);
      expect(line.declineReason, 'We do not carry 16 mm rebar');
    });

    test('an Available line decodes as available with no reason', () {
      final line = TokenVerification.fromJson(
        _verify([_line(available: true)]),
      ).items.single;

      expect(line.available, isTrue);
      expect(line.declineReason, '');
    });

    test('an unanswered line stays null, which is not false', () {
      // Decision 13: null means the store has not answered yet. Reading it as false
      // would hide a line that can still be handed over.
      for (final line in [
        TokenVerification.fromJson(
          _verify([_line(available: null)]),
        ).items.single,
        TokenVerification.fromJson(_verify([_line()])).items.single,
      ]) {
        expect(line.available, isNull);
        expect(line.declineReason, '');
      }
    });

    test('an available flag that is not a bool is a contract break', () {
      expect(
        () => TokenVerification.fromJson(_verify([_line(available: 'true')])),
        throwsFormatException,
      );
    });

    // Decision 13: a Not available line is never handed over, whatever the shelf holds,
    // and the project will never come back for it, so it cannot hold the token open.
    test('a Not available line never releases and never stays open', () {
      final line = TokenVerification.fromJson(
        _verify([
          _line(
            availability: 'FULL',
            releasable: '10.00',
            available: false,
            declineReason: 'We do not carry 16 mm rebar',
          ),
        ]),
      ).items.single;

      expect(line.isReleasable, isFalse);
      expect(line.goesNow, 0);
      expect(
        line.outstanding,
        0,
        reason:
            'nobody will ever hand over a line the store refused, so it must '
            'not keep the token alive or be promised as a return visit',
      );
    });

    test('an Available line still releases on the shelf\'s word', () {
      final line = TokenVerification.fromJson(
        _verify([
          _line(availability: 'SHORT', releasable: '4.00', available: true),
        ]),
      ).items.single;

      expect(line.isReleasable, isTrue);
      expect(line.goesNow, 4);
      expect(line.outstanding, 6);
    });

    test('an unanswered line keeps its prior behaviour and stays owed', () {
      // Decision 13: null/absent means the store has not answered, which is NOT a
      // refusal — the goods may still be collected, so the line reads exactly as it did
      // before the store decision existed.
      for (final unanswered in [null, _absent]) {
        final line = TokenVerification.fromJson(
          _verify([
            _line(
              availability: 'SHORT',
              releasable: '4.00',
              available: unanswered,
            ),
          ]),
        ).items.single;

        expect(line.available, isNull);
        expect(line.isReleasable, isTrue);
        expect(line.outstanding, 6);
      }
    });
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

    test(
      'open lines make the answer partial even when the status word is new',
      () {
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
      },
    );

    // Decision 13: RELEASED means every AVAILABLE line is out. A Not available line keeps
    // its outstanding quantity on the wire forever, but nobody will collect it, so the
    // receipt must not send the project back for it.
    test(
      'a Not available line with outstanding quantity leaves nothing open',
      () {
        final result = ReleaseResult.fromJson(
          _release(
            status: 'RELEASED',
            items: [
              {
                'code': 'CEM-40',
                'released_now': '10.00',
                'outstanding': '0.00',
                'available': true,
                'decline_reason': '',
              },
              {
                'code': 'STL-10',
                'released_now': '0.00',
                'outstanding': '6.00',
                'available': false,
                'decline_reason': 'We do not carry 16 mm rebar',
              },
            ],
          ),
        );

        expect(result.status, ReleaseStatus.released);
        expect(result.openLineCount, 0);
        expect(result.isPartial, isFalse);
        expect(
          result.items.last.outstanding,
          6,
          reason:
              'the wire keeps the recorded number; only the token ignores it',
        );
        expect(result.items.last.declineReason, 'We do not carry 16 mm rebar');
      },
    );

    test('a Not available line is not counted among a partial open lines', () {
      final result = ReleaseResult.fromJson(
        _release(
          status: 'PARTIAL',
          items: [
            {'code': 'STL-10', 'released_now': '4.00', 'outstanding': '6.00'},
            {
              'code': 'PLY-34',
              'released_now': '0.00',
              'outstanding': '12.00',
              'available': false,
              'decline_reason': 'Not stocked at this branch',
            },
          ],
        ),
      );

      expect(result.isPartial, isTrue);
      expect(result.openLineCount, 1);
    });
  });
}
