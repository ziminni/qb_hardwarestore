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

  test('a status this build was never taught still reads as unknown', () {
    expect(
      RequisitionStatus.fromApiValue('SOMETHING_NEW'),
      RequisitionStatus.unknown,
      reason: 'guessing a status is worse than admitting the client is behind',
    );
  });
}
