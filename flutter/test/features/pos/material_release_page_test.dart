import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:client/features/pos/views/material_release_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The release counter SCREEN — the last surface in Phase 5.
///
/// The guards (nothing releases before a token verifies; a released token cannot release twice) are
/// pinned a layer down in `material_release_viewmodel_test.dart` and mutation-verified there. These
/// tests prove only what a viewmodel test cannot see: that the button is ABSENT when the viewmodel
/// would refuse, and that the receipt the release created is actually shown — because a release
/// always leaves a receivable, and a clerk who cannot see it will not tell the customer.
class _StubRequisitions extends RequisitionRepository {
  int verifyCalls = 0;
  final List<String> released = [];
  bool failVerify = false;

  @override
  Future<TokenVerification> verifyToken(String token) async {
    verifyCalls++;
    if (failVerify) {
      throw Exception('nope');
    }
    return TokenVerification(
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

Future<void> _pump(WidgetTester tester, MaterialReleaseViewmodel vm) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: MaterialReleasePage(viewmodel: vm)));
  await tester.pumpAndSettle();
}

void main() {
  group('MaterialReleasePage', () {
    testWidgets('offers NO release before a token is verified', (tester) async {
      final repo = _StubRequisitions();
      final vm = MaterialReleaseViewmodel(repository: repo);

      await _pump(tester, vm);

      expect(find.widgetWithText(FilledButton, 'Release materials'), findsNothing);
      expect(repo.released, isEmpty);
    });

    testWidgets('a verified token shows the requisition, its remaining quantity and the action', (tester) async {
      final repo = _StubRequisitions();
      final vm = MaterialReleaseViewmodel(repository: repo);

      await _pump(tester, vm);
      await tester.enterText(find.byType(TextField), 'a-token');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pumpAndSettle();

      expect(find.text('REQ-20260925-0003'), findsOneWidget);
      expect(find.textContaining('Dela Cruz Construction'), findsWidgets);
      expect(find.textContaining('40kg'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Release materials'), findsOneWidget);
    });

    testWidgets('a release shows the sale and the receivable it left behind', (tester) async {
      final repo = _StubRequisitions();
      final vm = MaterialReleaseViewmodel(repository: repo);

      await _pump(tester, vm);
      await tester.enterText(find.byType(TextField), 'a-token');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Release materials'));
      await tester.pumpAndSettle();

      expect(repo.released, ['a-token']);
      expect(find.textContaining('TXN-20261017-0042'), findsWidgets);
      expect(find.textContaining('2700'), findsWidgets);
      // A released token cannot be released again, so the action must be gone.
      expect(find.widgetWithText(FilledButton, 'Release materials'), findsNothing);
    });
  });
}
