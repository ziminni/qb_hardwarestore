import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

/// The release counter — Phase 5's only IRREVERSIBLE action.
///
/// A release FIFO-deducts real stock, writes a real `SalesTransaction` and always creates a
/// receivable, so the rules that stop it firing wrongly are tested below the widget:
///
/// * **Nothing is released before a token is verified.** The server's own `release` calls
///   `verify_token` first, but a counter clerk must not be able to press the button at all without
///   a verified token, or the failure surfaces as a server error instead of an instruction.
/// * **A used token says so.** `verify_token` refuses an already-used token with
///   "Token has already been used.", and that is a *different instruction* to the clerk than
///   "Token not found." — one means ask for the right paper, the other means this paper is spent.
class _StubRequisitions extends RequisitionRepository {
  _StubRequisitions();

  int verifyCalls = 0;
  final List<String> released = [];
  Object? failVerify;
  Object? failRelease;
  TokenVerification? verification;
  ReleaseResult? releaseResult;

  @override
  Future<TokenVerification> verifyToken(String token) async {
    verifyCalls++;
    if (failVerify != null) throw failVerify!;
    return verification ??
        TokenVerification(
          token: token,
          requisitionId: 3,
          reqNumber: 'REQ-20260925-0003',
          project: '2-Storey House - Mandaue',
          customer: 'Dela Cruz Construction',
          items: const [
            VerifiedRequisitionItem(
              id: 1,
              variantId: 7,
              variantName: '40kg',
              quantity: 10,
              remaining: 10,
              availability: LineAvailability.full,
              releasable: 10,
            ),
          ],
        );
  }

  @override
  Future<ReleaseResult> release(String token) async {
    if (failRelease != null) throw failRelease!;
    released.add(token);
    return releaseResult ??
        const ReleaseResult(
          transactionId: 42,
          transactionNo: 'TXN-20261017-0042',
          status: ReleaseStatus.released,
          items: [],
          grandTotal: 2700,
          ledgerId: 9,
          balanceDue: 2700,
        );
  }
}

void main() {
  group('MaterialReleaseViewmodel', () {
    test(
      'verifying a token brings in the requisition and its remaining quantities',
      () async {
        final repo = _StubRequisitions();
        final vm = MaterialReleaseViewmodel(repository: repo);

        await vm.verify('a-token');

        expect(vm.verification?.reqNumber, 'REQ-20260925-0003');
        expect(vm.verification?.customer, 'Dela Cruz Construction');
        expect(vm.verification?.items.single.remaining, 10);
        expect(vm.error, isNull);
      },
    );

    test('an ALREADY USED token reports that, not "not found"', () async {
      final repo = _StubRequisitions();
      repo.failVerify = RequisitionServiceException(
        'Token has already been used.',
      );
      final vm = MaterialReleaseViewmodel(repository: repo);

      await vm.verify('spent-token');

      expect(vm.error, 'Token has already been used.');
      expect(vm.verification, isNull);
    });

    test('nothing is released before a token is verified', () async {
      final repo = _StubRequisitions();
      final vm = MaterialReleaseViewmodel(repository: repo);

      expect(await vm.release(), isFalse);

      expect(repo.released, isEmpty);
    });

    test(
      'a verified token releases and reports the sale and the receivable it created',
      () async {
        final repo = _StubRequisitions();
        final vm = MaterialReleaseViewmodel(repository: repo);
        await vm.verify('a-token');

        expect(await vm.release(), isTrue);

        expect(repo.released, ['a-token']);
        expect(vm.result?.transactionNo, 'TXN-20261017-0042');
        // A construction firm pays later, so a release ALWAYS leaves a balance.
        expect(vm.result?.balanceDue, 2700);
      },
    );

    test('a released token cannot be released a second time', () async {
      final repo = _StubRequisitions();
      final vm = MaterialReleaseViewmodel(repository: repo);
      await vm.verify('a-token');
      await vm.release();

      expect(await vm.release(), isFalse);
      expect(
        repo.released,
        hasLength(1),
        reason: 'the second press must send nothing',
      );
    });

    test("the server's refusal wins over the client's wording", () async {
      final repo = _StubRequisitions();
      final vm = MaterialReleaseViewmodel(repository: repo);
      await vm.verify('a-token');
      repo.failRelease = RequisitionServiceException(
        'Requisition is DRAFT, not APPROVED.',
      );

      expect(await vm.release(), isFalse);

      expect(vm.error, 'Requisition is DRAFT, not APPROVED.');
      expect(vm.result, isNull, reason: 'a refused release created nothing');
    });
  });


  // Phase 1, Task 9 (decision 05): a short shelf no longer refuses the whole release, so
  // the viewmodel has to know, BEFORE the irreversible press, whether anything can leave
  // the store at all, and what will stay open on the token afterwards.
  group('MaterialReleaseViewmodel: partial release', () {
    VerifiedRequisitionItem line({
      int id = 1,
      double quantity = 10,
      double remaining = 10,
      LineAvailability availability = LineAvailability.full,
      double releasable = 10,
      bool? available,
      String declineReason = '',
    }) => VerifiedRequisitionItem(
      id: id,
      variantId: id,
      variantName: 'line $id',
      quantity: quantity,
      remaining: remaining,
      availability: availability,
      releasable: releasable,
      available: available,
      declineReason: declineReason,
    );

    TokenVerification verified(List<VerifiedRequisitionItem> items) =>
        TokenVerification(
          token: 'a-token',
          requisitionId: 3,
          reqNumber: 'REQ-20260925-0003',
          project: '2-Storey House - Mandaue',
          customer: 'Dela Cruz Construction',
          items: items,
        );

    test('a verified token says whether anything can leave the store', () async {
      final repo = _StubRequisitions()
        ..verification = verified([
          line(),
          line(id: 2, availability: LineAvailability.short, releasable: 4),
          line(id: 3, availability: LineAvailability.unavailable, releasable: 0),
          line(
            id: 4,
            quantity: 24,
            remaining: 0,
            availability: LineAvailability.done,
            releasable: 0,
          ),
        ]);
      final vm = MaterialReleaseViewmodel(repository: repo);

      await vm.verify('a-token');

      expect(vm.hasReleasable, isTrue);
      expect(vm.confirmBlockedReason, isNull);
      expect(
        vm.leavesLinesOpen,
        isTrue,
        reason: 'the short and the out of stock line stay open on this token',
      );
      expect(vm.releasableLineCount, 2);
      expect(vm.totalLineCount, 4);
    });

    test('nothing releasable blocks the press and says why', () async {
      final repo = _StubRequisitions()
        ..verification = verified([
          line(availability: LineAvailability.unavailable, releasable: 0),
        ]);
      final vm = MaterialReleaseViewmodel(repository: repo);

      await vm.verify('a-token');

      expect(vm.hasReleasable, isFalse);
      expect(vm.confirmBlockedReason, contains('in stock right now'));
      expect(await vm.release(), isFalse);
      expect(
        repo.released,
        isEmpty,
        reason: 'the server would refuse, so the press must send nothing',
      );
    });

    test('every line already released names that, not an empty shelf', () async {
      final repo = _StubRequisitions()
        ..verification = verified([
          line(
            remaining: 0,
            availability: LineAvailability.done,
            releasable: 0,
          ),
        ]);
      final vm = MaterialReleaseViewmodel(repository: repo);

      await vm.verify('a-token');

      expect(vm.hasReleasable, isFalse);
      expect(vm.leavesLinesOpen, isFalse);
      expect(
        vm.confirmBlockedReason,
        contains('already released'),
        reason:
            'a clerk told the shelf is empty telephones the supplier; the '
            'truth is that this token is finished',
      );
    });

    // Decision 13: a line the store marked Not available is owed by nobody. It must not
    // count against the lines this scan promises, and it must not keep the token open.
    test('a Not available line is not a line this scan promises', () async {
      final repo = _StubRequisitions()
        ..verification = verified([
          line(),
          line(
            id: 2,
            availability: LineAvailability.unavailable,
            releasable: 0,
            available: false,
            declineReason: 'Not stocked at this branch',
          ),
        ]);
      final vm = MaterialReleaseViewmodel(repository: repo);

      await vm.verify('a-token');

      expect(vm.hasReleasable, isTrue);
      expect(vm.releasableLineCount, 1);
      expect(
        vm.totalLineCount,
        1,
        reason: 'a refused line is not part of what this request promises',
      );
      expect(
        vm.leavesLinesOpen,
        isFalse,
        reason: 'nobody will collect the refused line, so it stays closed',
      );
    });

    test('a finished token with a refused line left says it is done', () async {
      final repo = _StubRequisitions()
        ..verification = verified([
          line(
            remaining: 0,
            availability: LineAvailability.done,
            releasable: 0,
          ),
          line(
            id: 2,
            quantity: 5,
            remaining: 5,
            availability: LineAvailability.unavailable,
            releasable: 0,
            available: false,
            declineReason: 'We do not carry 16 mm rebar',
          ),
        ]);
      final vm = MaterialReleaseViewmodel(repository: repo);

      await vm.verify('a-token');

      expect(vm.hasReleasable, isFalse);
      expect(vm.leavesLinesOpen, isFalse);
      expect(
        vm.confirmBlockedReason,
        contains('already released'),
        reason:
            'the only line still owed is one the store refused; sending the '
            'project back for it would promise goods nobody will hand over',
      );
    });

    test('an unanswered line still leaves the token open', () async {
      // Fail-safe: absent/null eligibility means "nobody answered", not "refused", so
      // the conservative fallback and its open line stay exactly as before.
      final repo = _StubRequisitions()
        ..verification = verified([
          line(availability: LineAvailability.unavailable, releasable: 0),
        ]);
      final vm = MaterialReleaseViewmodel(repository: repo);

      await vm.verify('a-token');

      expect(vm.leavesLinesOpen, isTrue);
      expect(vm.confirmBlockedReason, contains('in stock right now'));
    });

    test('a release whose only outstanding line was refused is finished', () async {
      final repo = _StubRequisitions()
        ..verification = verified([line()])
        ..releaseResult = const ReleaseResult(
          transactionId: 42,
          transactionNo: 'TXN-20261017-0042',
          status: ReleaseStatus.released,
          items: [
            ReleasedLine(
              code: 'CEM-40',
              releasedNow: 10,
              outstanding: 0,
              available: true,
            ),
            ReleasedLine(
              code: 'STL-10',
              releasedNow: 0,
              outstanding: 6,
              available: false,
              declineReason: 'We do not carry 16 mm rebar',
            ),
          ],
          grandTotal: 2700,
          ledgerId: 9,
          balanceDue: 2700,
        );
      final vm = MaterialReleaseViewmodel(repository: repo);
      await vm.verify('a-token');

      expect(await vm.release(), isTrue);

      expect(vm.result?.isPartial, isFalse);
      expect(vm.openLineCount, 0);
    });

    test('a partial release reports the lines still open on the token', () async {
      final repo = _StubRequisitions()
        ..verification = verified([
          line(),
          line(id: 2, availability: LineAvailability.short, releasable: 4),
        ])
        ..releaseResult = const ReleaseResult(
          transactionId: 42,
          transactionNo: 'TXN-20261017-0042',
          status: ReleaseStatus.partial,
          items: [
            ReleasedLine(code: 'CEM-40', releasedNow: 10, outstanding: 0),
            ReleasedLine(code: 'STL-10', releasedNow: 4, outstanding: 6),
          ],
          grandTotal: 2700,
          ledgerId: 9,
          balanceDue: 2700,
        );
      final vm = MaterialReleaseViewmodel(repository: repo);
      await vm.verify('a-token');

      expect(await vm.release(), isTrue);

      expect(vm.result?.isPartial, isTrue);
      expect(vm.openLineCount, 1);
    });

    test('a second scan of the same token starts from the server again', () async {
      // The first scan released part of the request; the second must not reuse the first
      // scan's lines, its result, or its blocked reason.
      final repo = _StubRequisitions()..verification = verified([line()]);
      final vm = MaterialReleaseViewmodel(repository: repo);
      await vm.verify('a-token');
      await vm.release();

      repo.verification = verified([
        line(
          remaining: 0,
          availability: LineAvailability.done,
          releasable: 0,
        ),
      ]);
      await vm.verify('a-token');

      expect(
        vm.result,
        isNull,
        reason: 'the last release receipt must not sit over the new scan',
      );
      expect(vm.hasReleasable, isFalse);
      expect(vm.confirmBlockedReason, contains('already released'));
      expect(repo.verifyCalls, 2);
    });
  });
}
