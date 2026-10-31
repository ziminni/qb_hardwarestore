import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:client/features/pos/views/material_release_page.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

Future<void> _pump(
  WidgetTester tester,
  MaterialReleaseViewmodel vm, {
  Size size = const Size(1600, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(home: MaterialReleasePage(viewmodel: vm)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('MaterialReleasePage', () {
    testWidgets('offers NO release before a token is verified', (tester) async {
      final repo = _StubRequisitions();
      final vm = MaterialReleaseViewmodel(repository: repo);

      await _pump(tester, vm);

      expect(
        find.widgetWithText(FilledButton, 'Release materials'),
        findsNothing,
      );
      expect(repo.released, isEmpty);
    });

    testWidgets(
      'a verified token shows the requisition, its remaining quantity and the action',
      (tester) async {
        final repo = _StubRequisitions();
        final vm = MaterialReleaseViewmodel(repository: repo);

        await _pump(tester, vm);
        await tester.enterText(find.byType(TextField), 'a-token');
        // The field enables the button on its next frame.
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
        await tester.pumpAndSettle();

        expect(find.text('REQ-20260925-0003'), findsOneWidget);
        expect(find.textContaining('Dela Cruz Construction'), findsWidgets);
        expect(find.textContaining('40kg'), findsWidgets);
        expect(
          find.widgetWithText(FilledButton, 'Release materials'),
          findsOneWidget,
        );
      },
    );

    testWidgets('a release shows the sale and the receivable it left behind', (
      tester,
    ) async {
      final repo = _StubRequisitions();
      final vm = MaterialReleaseViewmodel(repository: repo);

      await _pump(tester, vm);
      await tester.enterText(find.byType(TextField), 'a-token');
      // The field enables the button on its next frame.
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Release materials'));
      await tester.pumpAndSettle();

      expect(repo.released, ['a-token']);
      expect(find.textContaining('TXN-20261017-0042'), findsWidgets);
      expect(find.textContaining('2,700'), findsWidgets);
      // A released token cannot be released again, so the action must be gone.
      expect(
        find.widgetWithText(FilledButton, 'Release materials'),
        findsNothing,
      );
    });

    testWidgets('"Verify another token" clears the screen for the next one', (
      tester,
    ) async {
      final vm = MaterialReleaseViewmodel(repository: _StubRequisitions());

      await _pump(tester, vm);
      await tester.enterText(find.byType(TextField), 'a-token');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Release materials'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Verify another token'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Verify another token'),
      );
      await tester.pumpAndSettle();

      // The field and every step go back to their starting state: the next
      // foreman's token must not be released against the last one's lines.
      expect(find.text('a-token'), findsNothing);
      expect(vm.verification, isNull);
      expect(vm.result, isNull);
      expect(find.text('REQ-20260925-0003'), findsNothing);
      expect(find.textContaining('TXN-20261017-0042'), findsNothing);
      expect(find.text('Review the requisition'), findsOneWidget);
    });

    testWidgets('Enter in the token field verifies the token', (tester) async {
      final repo = _StubRequisitions();
      final vm = MaterialReleaseViewmodel(repository: repo);

      await _pump(tester, vm);
      await tester.enterText(find.byType(TextField), 'a-token');
      // The clerk has a printed token and a keyboard. Pressing Enter is the
      // whole interaction; reaching for the button is a second step nobody
      // does at a counter.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(
        repo.verifyCalls,
        1,
        reason: 'Enter in the one field on this screen must verify the token',
      );
      expect(find.text('REQ-20260925-0003'), findsOneWidget);
    });

    testWidgets('the page does not scroll inside the shell scroll', (
      tester,
    ) async {
      final vm = MaterialReleaseViewmodel(repository: _StubRequisitions());

      await _pump(tester, vm, size: const Size(1400, 900));

      expect(
        find.byType(SingleChildScrollView),
        findsOneWidget,
        reason:
            'the shell already scrolls the page body; a second scroll view '
            'cuts the content off at the bottom of a fixed box',
      );
      // 900 is the window height, so the old fixed box was 900 - 132 = 768.
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height == 768,
        ),
        findsNothing,
        reason:
            'a height that subtracts the header from the window clips the page '
            'on every window the design did not measure',
      );
    });

    testWidgets('the three steps are shown in order, narrow first', (
      tester,
    ) async {
      final vm = MaterialReleaseViewmodel(repository: _StubRequisitions());

      await _pump(tester, vm, size: const Size(760, 900));

      const titles = [
        'Verify the token',
        'Review the requisition',
        'Release receipt',
      ];
      for (final title in titles) {
        expect(
          find.text(title),
          findsOneWidget,
          reason: 'the clerk must see step "$title" before doing it',
        );
      }

      final tops = [
        for (final title in titles) tester.getTopLeft(find.text(title)).dy,
      ];
      expect(
        tops[0] < tops[1] && tops[1] < tops[2],
        isTrue,
        reason:
            'verify, then review, then the receipt reads top to bottom: $tops',
      );
    });
  });
}
