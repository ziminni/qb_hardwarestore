// Phase 3 Task 4 / decision 03: a material release now REQUIRES the releasing
// cashier's open shift.
//
// The backend change (`release_materials` -> 400 `NO_OPEN_SHIFT`, Phase 3 Task 1)
// makes the release write a `SalesTransaction` against a shift, so the Z-reading
// counts it in the transaction count and gross sales. That means the till's
// release screen must do what the till itself does when there is no shift: say
// so, and point at the Shifts tab.
//
// WHY THE CLIENT CODE MAPS THE CODE AND NOT THE PROSE: "no open shift" is the one
// release refusal with a NEXT STEP the screen can take on the clerk's behalf. A
// transport failure whose prose happened to mention a shift must not put a "Go to
// Shifts" button on the screen, so the decision is made on `code`, never on the
// text.

import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:client/features/pos/views/material_release_page.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _StubRequisitions extends RequisitionRepository {
  _StubRequisitions();

  final List<String> released = [];
  Object? failRelease;

  @override
  Future<TokenVerification> verifyToken(String token) async => TokenVerification(
    token: token,
    requisitionId: 3,
    reqNumber: 'REQ-20261024-0003',
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

  @override
  Future<ReleaseResult> release(String token) async {
    if (failRelease != null) throw failRelease!;
    released.add(token);
    return const ReleaseResult(
      transactionId: 42,
      transactionNo: 'TXN-20261024-0042',
      grandTotal: 2700,
      ledgerId: 9,
      balanceDue: 2700,
    );
  }
}

void main() {
  group('MaterialReleaseViewmodel: NO_OPEN_SHIFT is a rule with a next step', () {
    test('the refusal sets needsOpenShift and the shift instruction', () async {
      final repo = _StubRequisitions()
        ..failRelease = const RequisitionServiceException(
          'You have no open shift. Open a shift before releasing materials.',
          code: 'NO_OPEN_SHIFT',
        );
      final viewmodel = MaterialReleaseViewmodel(repository: repo);
      await viewmodel.verify('a-token');

      expect(
        await viewmodel.release(),
        isFalse,
        reason: 'nothing was released, so the press did not succeed',
      );

      expect(
        viewmodel.needsOpenShift,
        isTrue,
        reason:
            'the screen needs to know this is a RULE it can fix, not a failure '
            'worth retrying',
      );
      expect(viewmodel.error, contains('Open a shift before releasing'));
      expect(viewmodel.result, isNull);
    });

    test('another refusal does NOT offer the shift detour', () async {
      final repo = _StubRequisitions()
        ..failRelease = const RequisitionServiceException(
          'Token has already been used.',
        );
      final viewmodel = MaterialReleaseViewmodel(repository: repo);
      await viewmodel.verify('a-token');

      expect(await viewmodel.release(), isFalse);

      expect(
        viewmodel.needsOpenShift,
        isFalse,
        reason:
            'a spent token is not fixed by opening a shift, and offering that '
            'detour would send the clerk on a pointless walk',
      );
    });
  });

  group('MaterialReleasePage', () {
    Future<MaterialReleaseViewmodel> pump(
      WidgetTester tester, {
      required RequisitionRepository repository,
      List<String> visitedRoutes = const [],
    }) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final viewmodel = MaterialReleaseViewmodel(repository: repository);
      final router = GoRouter(
        initialLocation: AppRoutes.posRelease,
        routes: [
          GoRoute(
            path: AppRoutes.posRelease,
            builder: (context, state) =>
                MaterialReleasePage(viewmodel: viewmodel),
          ),
          GoRoute(
            path: AppRoutes.posShifts,
            builder: (context, state) {
              visitedRoutes.add(AppRoutes.posShifts);
              return const Scaffold(body: Text('SHIFTS PAGE'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: AuthViewmodel(AuthRepository(AuthService())),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      return viewmodel;
    }

    testWidgets('a NO_OPEN_SHIFT refusal explains it and offers the Shifts tab', (
      tester,
    ) async {
      final repo = _StubRequisitions()
        ..failRelease = const RequisitionServiceException(
          'You have no open shift. Open a shift before releasing materials.',
          code: 'NO_OPEN_SHIFT',
        );
      final visited = <String>[];
      await pump(tester, repository: repo, visitedRoutes: visited);

      await tester.enterText(find.byType(TextField).first, 'b1e0-token');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Release materials'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Open a shift before releasing'),
        findsOneWidget,
        reason: 'the clerk must be told the rule, not shown a generic failure',
      );

      final goToShifts = find.widgetWithText(OutlinedButton, 'Go to Shifts');
      expect(
        goToShifts,
        findsOneWidget,
        reason:
            'a refusal the clerk can fix deserves the control that fixes it — '
            'otherwise it is a dead end',
      );

      await tester.tap(goToShifts);
      await tester.pumpAndSettle();

      expect(visited, [AppRoutes.posShifts]);
      expect(find.text('SHIFTS PAGE'), findsOneWidget);
    });

    testWidgets('the token stays entered while the clerk opens a shift', (
      tester,
    ) async {
      final repo = _StubRequisitions()
        ..failRelease = const RequisitionServiceException(
          'You have no open shift.',
          code: 'NO_OPEN_SHIFT',
        );
      await pump(tester, repository: repo);

      await tester.enterText(find.byType(TextField).first, 'b1e0-token');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Release materials'));
      await tester.pumpAndSettle();

      expect(
        find.text('b1e0-token'),
        findsOneWidget,
        reason:
            'retyping a 36-character UUID after opening a shift is how a clerk '
            'releases the wrong requisition',
      );
    });

    testWidgets('no shift detour is offered for an unrelated refusal', (
      tester,
    ) async {
      final repo = _StubRequisitions()
        ..failRelease = const RequisitionServiceException(
          'Token has already been used.',
        );
      await pump(tester, repository: repo);

      await tester.enterText(find.byType(TextField).first, 'a-token');
      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Release materials'));
      await tester.pumpAndSettle();

      expect(find.text('Token has already been used.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Go to Shifts'), findsNothing);
    });
  });
}
