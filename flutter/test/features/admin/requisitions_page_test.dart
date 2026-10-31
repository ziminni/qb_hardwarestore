import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/admin/viewmodels/admin_requisitions_viewmodel.dart';
import 'package:client/features/admin/views/requisitions_page.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The queue SCREEN: what a Store Manager actually sees and can press.
///
/// The gate itself (only SUBMITTED is actionable) is pinned a layer down in
/// `admin_requisitions_viewmodel_test.dart`, so these tests do NOT re-prove it. They prove the
/// screen renders the provenance decision 09 requires, that an approval is CONFIRMED and names the
/// goods before anything is written (D16), that the queue is filtered by status, and that it fills
/// its own slot in both shells it is served from.
class _StubRequisitions extends RequisitionRepository {
  _StubRequisitions(this.rows);
  final List<Requisition> rows;
  final List<int> approved = [];
  final List<int> rejected = [];
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

  @override
  Future<void> reject(int requisitionId) async {
    rejected.add(requisitionId);
  }
}

RequisitionItem _item(
  int id,
  String name,
  double quantity, {
  double released = 0,
}) => RequisitionItem(
  id: id,
  variantId: id,
  variantName: name,
  quantity: quantity,
  releasedQty: released,
);

Requisition _req(
  int id,
  String status, {
  List<RequisitionItem> items = const [],
  String? token,
}) => Requisition(
  id: id,
  reqNumber: 'REQ-000$id',
  rawStatus: status,
  projectName: '2-Storey House - Mandaue',
  projectCustomerName: 'Dela Cruz Construction',
  requestedByName: 'Fore Man',
  items: items,
  token: token,
);

Future<void> _pump(
  WidgetTester tester,
  AdminRequisitionsViewmodel vm, {
  bool inSalesShell = false,
}) async {
  // The admin shell watches AuthViewmodel, so it must be above the MaterialApp or every test
  // dies with ProviderNotFoundException; and the shell overflows the default 800x600 surface.
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        home: RequisitionsPage(viewmodel: vm, inSalesShell: inSalesShell),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The confirmation's own Approve, so the row's button is never double counted.
Finder _dialogButton(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(FilledButton, label),
);

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
      'Approve asks first and names every item with its quantity (D16)',
      (tester) async {
        final repo = _StubRequisitions([
          _req(
            2,
            'SUBMITTED',
            items: [
              _item(1, 'Portland Cement 40kg', 10),
              _item(2, 'Deformed Steel Bar 10mm', 2.5),
            ],
          ),
        ]);
        final vm = AdminRequisitionsViewmodel(repository: repo);

        await _pump(tester, vm);
        await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
        await tester.pumpAndSettle();

        expect(
          repo.approved,
          isEmpty,
          reason: 'nothing may be written before the manager confirms',
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('REQ-0002'), findsWidgets);
        expect(
          find.textContaining('10 × Portland Cement 40kg'),
          findsOneWidget,
          reason: 'the confirmation names what is being approved',
        );
        expect(
          find.textContaining('2.5 × Deformed Steel Bar 10mm'),
          findsOneWidget,
        );

        await tester.tap(_dialogButton('Approve'));
        await tester.pumpAndSettle();

        expect(repo.approved, [2]);
      },
    );

    testWidgets('Approve cancelled sends nothing at all', (tester) async {
      final repo = _StubRequisitions([_req(1, 'SUBMITTED')]);
      final vm = AdminRequisitionsViewmodel(repository: repo);

      await _pump(tester, vm);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Keep waiting'));
      await tester.pumpAndSettle();

      expect(repo.approved, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('Reject asks for confirmation, and only then rejects', (
      tester,
    ) async {
      final repo = _StubRequisitions([_req(1, 'SUBMITTED')]);
      final vm = AdminRequisitionsViewmodel(repository: repo);

      await _pump(tester, vm);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject'));
      await tester.pumpAndSettle();

      expect(repo.rejected, isEmpty);
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(_dialogButton('Reject'));
      await tester.pumpAndSettle();

      expect(repo.rejected, [1]);
    });

    testWidgets('status chips count each state and filter the queue', (
      tester,
    ) async {
      final vm = AdminRequisitionsViewmodel(
        repository: _StubRequisitions([
          _req(1, 'SUBMITTED'),
          _req(2, 'SUBMITTED'),
          _req(3, 'APPROVED', token: 'token-approved'),
          _req(4, 'RELEASED', token: 'token-released'),
          _req(5, 'REJECTED'),
        ]),
      );

      await _pump(tester, vm);

      final chips = find.byType(FilterBar);
      expect(
        find.descendant(
          of: chips,
          matching: find.text('Awaiting approval (2)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('Approved (1)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('Released (1)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('Rejected (1)')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(of: chips, matching: find.text('Released (1)')),
      );
      await tester.pumpAndSettle();

      expect(find.text('REQ-0004'), findsOneWidget);
      expect(find.text('REQ-0001'), findsNothing);
      expect(find.text('REQ-0003'), findsNothing);
    });

    testWidgets('the admin shell gives the queue its own scrolling slot', (
      tester,
    ) async {
      final vm = AdminRequisitionsViewmodel(
        repository: _StubRequisitions([_req(1, 'SUBMITTED')]),
      );

      await _pump(tester, vm);

      final layout = tester.widget<AdminSkeletonLayout>(
        find.byType(AdminSkeletonLayout),
      );
      expect(
        layout.scrollable,
        isFalse,
        reason: 'a long queue builds only the rows on screen',
      );
      expect(find.byType(SalesSkeletonLayout), findsNothing);
      expect(find.byType(FilterBar), findsOneWidget);
      expect(find.text('REQ-0001'), findsOneWidget);
    });

    testWidgets('the Store Manager shell shows the same queue and filters', (
      tester,
    ) async {
      final vm = AdminRequisitionsViewmodel(
        repository: _StubRequisitions([_req(1, 'SUBMITTED')]),
      );

      await _pump(tester, vm, inSalesShell: true);

      final layout = tester.widget<SalesSkeletonLayout>(
        find.byType(SalesSkeletonLayout),
      );
      expect(layout.selectedNavigationIndex, 7);
      expect(layout.scrollable, isFalse);
      expect(find.byType(AdminSkeletonLayout), findsNothing);
      expect(find.byType(FilterBar), findsOneWidget);
      expect(find.text('REQ-0001'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
    });

    testWidgets('a failed load says so instead of showing an empty queue', (
      tester,
    ) async {
      // "Nothing awaiting approval" and "we could not read the list" must not look the same.
      final repo = _StubRequisitions(const []);
      repo.failFetch = true;
      final vm = AdminRequisitionsViewmodel(repository: repo);

      await _pump(tester, vm);

      expect(find.textContaining('could not be loaded'), findsOneWidget);
      expect(
        find.text('No material requisitions yet.'),
        findsNothing,
        reason: 'one failure, never an empty state underneath it',
      );
    });

    testWidgets('an empty queue says so', (tester) async {
      final vm = AdminRequisitionsViewmodel(
        repository: _StubRequisitions(const []),
      );

      await _pump(tester, vm);

      expect(find.text('No material requisitions yet.'), findsOneWidget);
    });
  });
}
