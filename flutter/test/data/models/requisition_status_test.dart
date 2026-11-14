// Task 10 (decisions 06 and 08): the POS shows what CPMS left behind.
//
// `CLOSED` is a request whose open remainder CPMS closed, and `PARTIAL` is one the till
// released short. Both used to fall through to `unknown`, so the reports screen printed the
// server's raw token instead of a word, and a manager reading the Requisitions tab could not
// tell a closed request from one this build had never heard of.
import 'package:client/data/models/requisition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('CLOSED reads as Closed', () {
    expect(
      RequisitionStatus.fromApiValue('CLOSED').label,
      'Closed',
      reason: 'a closed remainder is a decision, not an unknown status',
    );
  });

  test('PARTIAL reads as Partially released', () {
    expect(
      RequisitionStatus.fromApiValue('PARTIAL').label,
      'Partially released',
      reason: 'the till has to be able to say what it did not hand over',
    );
  });

  test('every status the POS writes today has a label of its own', () {
    // The CPMS-side statuses plus the two the till writes (decision 05).
    for (final api in const [
      'DRAFT',
      'APPROVED',
      'PARTIAL',
      'RELEASED',
      'CLOSED',
      // Decision 08: the migration turned old drafts into CANCELLED rows.
      'CANCELLED',
    ]) {
      final status = RequisitionStatus.fromApiValue(api);
      expect(
        status,
        isNot(RequisitionStatus.unknown),
        reason: '$api must not read as unknown',
      );
      expect(status.label, isNotEmpty);
    }
  });

  // Phase 1b (decisions 09/10/13): the store answers a pushed request. WAITING is
  // what CPMS pushes, ACCEPTED replaced APPROVED, and DECLINED is the store's refusal.
  test('WAITING reads as Waiting for store', () {
    expect(
      RequisitionStatus.fromApiValue('WAITING').label,
      'Waiting for store',
      reason: 'a request nobody answered is not a draft and not an approval',
    );
  });

  test('ACCEPTED reads as Accepted', () {
    expect(RequisitionStatus.fromApiValue('ACCEPTED').label, 'Accepted');
  });

  test('DECLINED reads as Declined', () {
    expect(RequisitionStatus.fromApiValue('DECLINED').label, 'Declined');
  });

  test('APPROVED is still readable, because history keeps that word', () {
    // Decision 13: no new row enters APPROVED, but every row that held it before the
    // upgrade keeps reading as an approval rather than as an unknown status.
    expect(RequisitionStatus.fromApiValue('APPROVED').label, 'Approved');
    expect(
      RequisitionStatus.fromApiValue('APPROVED'),
      isNot(RequisitionStatus.accepted),
      reason: 'the raw status stays distinguishable in a report',
    );
    expect(RequisitionStatus.approved.apiValue, 'APPROVED');
    expect(RequisitionStatus.accepted.apiValue, 'ACCEPTED');
  });

  test('the three new words are distinct statuses, not aliases', () {
    expect(
      {
        RequisitionStatus.fromApiValue('WAITING'),
        RequisitionStatus.fromApiValue('ACCEPTED'),
        RequisitionStatus.fromApiValue('DECLINED'),
      },
      {
        RequisitionStatus.waiting,
        RequisitionStatus.accepted,
        RequisitionStatus.declined,
      },
    );
  });

  test('a status this build was never taught still reads as unknown', () {
    expect(
      RequisitionStatus.fromApiValue('SOMETHING_NEW'),
      RequisitionStatus.unknown,
      reason: 'guessing a status is worse than admitting the client is behind',
    );
  });
}
