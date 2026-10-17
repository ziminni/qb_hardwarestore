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
            ),
          ],
        );
  }

  @override
  Future<ReleaseResult> release(String token) async {
    if (failRelease != null) throw failRelease!;
    released.add(token);
    return const ReleaseResult(
      transactionId: 42,
      transactionNo: 'TXN-20261017-0042',
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
}
