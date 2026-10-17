import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/admin/viewmodels/admin_requisitions_viewmodel.dart';
import 'package:client/features/admin/views/requisitions_page.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The queue SCREEN: what a Store Manager actually sees and can press.
///
/// The gate itself (only SUBMITTED is actionable) is pinned a layer down in
/// `admin_requisitions_viewmodel_test.dart`, so these tests do NOT re-prove it. They prove the
/// screen renders the provenance decision 09 requires and puts the button on the right rows —
/// the part a viewmodel test cannot see.
class _StubRequisitions extends RequisitionRepository {
  _StubRequisitions(this.rows);
  final List<Requisition> rows;
  final List<int> approved = [];
  bool failFetch = false;

  @override
  Future<List<Requisition>> fetchRequisitions() async {
    if (failFetch) {
      throw RequisitionServiceException(
        'The requisitions could not be loaded.',
      );
    }
    return rows;
  }

  @override
  Future<String> approve(int requisitionId) async {
    approved.add(requisitionId);
    return 'token-$requisitionId';
  }
}

Requisition _req(int id, String status) => Requisition(
  id: id,
  reqNumber: 'REQ-000$id',
  rawStatus: status,
  projectName: '2-Storey House - Mandaue',
  projectCustomerName: 'Dela Cruz Construction',
  requestedByName: 'Fore Man',
  items: const [],
  token: null,
);

Future<void> _pump(WidgetTester tester, AdminRequisitionsViewmodel vm) async {
  // The admin shell watches AuthViewmodel, so it must be above the MaterialApp or every test
  // dies with ProviderNotFoundException; and the shell overflows the default 800x600 surface.
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(home: RequisitionsPage(viewmodel: vm)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('RequisitionsPage', () {
    testWidgets('shows all four provenance facts decision 09 requires', (
      tester,
    ) async {
      final vm = AdminRequisitionsViewmodel(
        repository: _StubRequisitions([_req(1, 'SUBMITTED')]),
      );

      await _pump(tester, vm);

      expect(find.text('REQ-0001'), findsOneWidget);
      expect(find.textContaining('2-Storey House - Mandaue'), findsWidgets);
      expect(find.textContaining('Dela Cruz Construction'), findsWidgets);
      expect(find.textContaining('Fore Man'), findsWidgets);
    });

    testWidgets('offers Approve on a SUBMITTED row and NOT on a DRAFT row', (
      tester,
    ) async {
      final vm = AdminRequisitionsViewmodel(
        repository: _StubRequisitions([_req(1, 'SUBMITTED'), _req(2, 'DRAFT')]),
      );

      await _pump(tester, vm);

      expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
      expect(
        find.text('REQ-0002'),
        findsOneWidget,
        reason: 'the DRAFT row is still listed',
      );
    });

    testWidgets(
      'pressing Approve reaches the repository and the row leaves the queue',
      (tester) async {
        final repo = _StubRequisitions([_req(1, 'SUBMITTED')]);
        final vm = AdminRequisitionsViewmodel(repository: repo);

        await _pump(tester, vm);
        await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
        await tester.pumpAndSettle();

        expect(repo.approved, [1]);
        expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);
      },
    );

    testWidgets('a failed load says so instead of showing an empty queue', (
      tester,
    ) async {
      // "Nothing awaiting approval" and "we could not read the list" must not look the same.
      final repo = _StubRequisitions(const []);
      repo.failFetch = true;
      final vm = AdminRequisitionsViewmodel(repository: repo);

      await _pump(tester, vm);

      expect(find.textContaining('could not be loaded'), findsOneWidget);
    });
  });
}
