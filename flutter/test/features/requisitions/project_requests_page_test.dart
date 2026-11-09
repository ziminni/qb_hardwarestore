// Phase 1b Task 7 (decisions 09, 10, 13 and 14): the shared "Requests from
// projects" screen, at the three widths and two text scales the plan asks for.
//
// Pinned here, one property per test:
//   * the queue lists the selected status oldest-first and offers Review only
//     for WAITING; every other status opens read-only detail,
//   * the sidebar badge is the ALL-waiting count: independent of the search and
//     the status chip, and a missing count is never drawn as 0,
//   * the review dialog refuses an all-false Accept (with Decline as the way
//     out) and a Not-available line with no reason, before any request,
//   * a saved decision closes the dialog and says so; the money line follows
//     decision 14 (never ₱0.00 for an unknown expected amount),
//   * nothing clips at 1440/1100/760 or at text scale 1.3.
import 'dart:io';

import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/requisitions/viewmodels/project_requests_viewmodel.dart';
import 'package:client/features/requisitions/views/project_requests_page.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

RequisitionItem _line({
  int id = 21,
  String productName = 'Portland Cement',
  String variantName = '40 kg',
  String unit = '40 kg bag',
  double quantity = 4,
  bool? available,
  String declineReason = '',
}) => RequisitionItem(
  id: id,
  variantId: 4,
  variantName: variantName,
  quantity: quantity,
  releasedQty: 0,
  productName: productName,
  unit: unit,
  available: available,
  declineReason: declineReason,
);

Requisition _request({
  int id = 7,
  String reqNumber = 'REQ-20261107-0007',
  String status = 'WAITING',
  String project = '2-Storey House - Mandaue',
  String customer = 'Dela Cruz Construction',
  String requestedBy = 'Forman Reyes',
  String? approver = 'Engr. Reyes',
  String notes = 'Deliver to gate 2 before noon.',
  String declineReason = '',
  double? expectedAmount,
  List<RequisitionItem>? items,
}) => Requisition(
  id: id,
  reqNumber: reqNumber,
  rawStatus: status,
  projectName: project,
  projectCustomerName: customer,
  requestedByName: requestedBy,
  items: items ?? [_line()],
  cpmsRequestId: 'CPMS-REQ-8842',
  createdAt: DateTime(2026, 11, 7, 8, 15),
  approverName: approver,
  notes: notes,
  declineReason: declineReason,
  expectedAmount: expectedAmount,
);

class _StubRepository extends RequisitionRepository {
  _StubRepository() : super();

  List<Requisition> rows = const [];
  int waiting = 0;
  String? listError;
  String? countError;
  String? detailError;
  Requisition? detail;
  Requisition? writeResult;
  RequisitionServiceException? writeError;
  int acceptCalls = 0;
  int detailCalls = 0;
  List<RequisitionLineDecision>? lastDecisions;
  String? lastReason;

  @override
  Future<List<Requisition>> fetchRequisitions({String? status}) async {
    final failure = listError;
    if (failure != null) throw RequisitionServiceException(failure);
    if (status == null) return rows;
    return rows.where((row) => row.rawStatus == status).toList();
  }

  @override
  Future<int> waitingCount() async {
    final failure = countError;
    if (failure != null) throw RequisitionServiceException(failure);
    return waiting;
  }

  @override
  Future<Requisition> fetchRequisition(int id) async {
    detailCalls++;
    final failure = detailError;
    if (failure != null) throw RequisitionServiceException(failure);
    return detail ?? rows.firstWhere((row) => row.id == id);
  }

  @override
  Future<Requisition> accept(
    int id,
    List<RequisitionLineDecision> decisions,
  ) async {
    acceptCalls++;
    lastDecisions = decisions;
    final failure = writeError;
    if (failure != null) throw failure;
    return writeResult ??
        _request(id: id, status: 'ACCEPTED', expectedAmount: 1260);
  }

  @override
  Future<Requisition> decline(int id, String reason) async {
    lastReason = reason;
    final failure = writeError;
    if (failure != null) throw failure;
    return writeResult ??
        _request(id: id, status: 'DECLINED', declineReason: reason);
  }
}

AuthViewmodel _auth({
  String role = 'sales',
  String roleLabel = 'Store Manager',
}) {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth.user = User(
    id: 1,
    username: role,
    email: '$role@qb.local',
    fullName: 'Maria Santos',
    role: Role(id: 1, name: role, displayName: roleLabel),
  );
  return auth;
}

Future<ProjectRequestsViewmodel> _pump(
  WidgetTester tester, {
  required _StubRepository repository,
  Size size = const Size(1600, 1400),
  double textScale = 1,
  bool adminShell = false,
  bool appTheme = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final viewmodel = ProjectRequestsViewmodel(repository: repository);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: _auth(role: adminShell ? 'admin' : 'sales'),
      child: MaterialApp(
        theme: appTheme ? AppTheme.lightTheme : null,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: adminShell
            ? AdminProjectRequestsPage(viewmodel: viewmodel)
            : ProjectRequestsPage(viewmodel: viewmodel),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return viewmodel;
}

Future<void> _openReview(WidgetTester tester) async {
  await tester.tap(find.text('Review'));
  await tester.pumpAndSettle();
}

void main() {
  group('the queue', () {
    testWidgets('lists the waiting request with its project and requester', (
      tester,
    ) async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..waiting = 1;
      await _pump(tester, repository: repository);

      expect(find.text('REQ-20261107-0007'), findsOneWidget);
      expect(find.text('2-Storey House - Mandaue'), findsOneWidget);
      expect(find.text('Dela Cruz Construction'), findsOneWidget);
      expect(find.text('Forman Reyes'), findsOneWidget);
      expect(find.text('Nov 7, 2026'), findsOneWidget);
      expect(find.text('Waiting for store'), findsWidgets);
      expect(find.text('Review'), findsOneWidget);
    });

    testWidgets('a reviewed status opens read-only detail, not a review', (
      tester,
    ) async {
      final repository = _StubRepository()
        ..rows = [_request(status: 'ACCEPTED', expectedAmount: 1260)];
      await _pump(tester, repository: repository);

      await tester.tap(find.text('Accepted'));
      await tester.pumpAndSettle();
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Review'), findsNothing);

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text('Accept request'), findsNothing);
      expect(find.text('Decline request'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
      expect(find.text('Expected amount, not yet owed'), findsOneWidget);
      expect(find.text('₱1,260.00'), findsOneWidget);
    });

    testWidgets('a truthful empty state per selection and search', (
      tester,
    ) async {
      final repository = _StubRepository();
      await _pump(tester, repository: repository);

      expect(
        find.text('No requests are waiting for the store.'),
        findsOneWidget,
      );

      repository.rows = [_request()];
      await tester.tap(find.text('Accepted'));
      await tester.pumpAndSettle();
      expect(find.text('No requests in this status.'), findsOneWidget);

      await tester.tap(find.text('Waiting for store').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'nothing matches');
      await tester.pumpAndSettle();
      expect(find.text('No requests match this search.'), findsOneWidget);
    });

    testWidgets('a reload failure keeps the rows and says why', (tester) async {
      final repository = _StubRepository()..rows = [_request()];
      await _pump(tester, repository: repository);
      expect(find.text('REQ-20261107-0007'), findsOneWidget);

      repository.listError = 'Server down.';
      await tester.tap(find.byKey(const Key('refresh-requests')));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(find.text('Server down.'), findsOneWidget);
      expect(
        find.text('REQ-20261107-0007'),
        findsOneWidget,
        reason: 'a failed reload must not empty the queue',
      );
    });

    testWidgets('the admin shell renders the same queue', (tester) async {
      final repository = _StubRepository()..rows = [_request()];
      await _pump(tester, repository: repository, adminShell: true);

      expect(find.byType(AdminSkeletonLayout), findsOneWidget);
      expect(find.text('REQ-20261107-0007'), findsOneWidget);
      final layout = tester.widget<AdminSkeletonLayout>(
        find.byType(AdminSkeletonLayout),
      );
      expect(layout.selectedNavigationIndex, 7);
      expect(layout.title, 'Requests from projects');
    });
  });

  group('the sidebar badge', () {
    testWidgets('shows the server count on the queue entry', (tester) async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..waiting = 3;
      await _pump(tester, repository: repository);

      final marker = find.byKey(const ValueKey('sidebar-marker-8'));
      expect(marker, findsOneWidget);
      expect(
        find.descendant(of: marker, matching: find.text('3')),
        findsOneWidget,
      );
    });

    testWidgets('ignores the search and the status chip', (tester) async {
      final repository = _StubRepository()
        ..rows = [_request(), _request(id: 8, status: 'ACCEPTED')]
        ..waiting = 3;
      await _pump(tester, repository: repository);

      await tester.enterText(find.byType(TextField).first, 'no such project');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sidebar-marker-8')), findsOneWidget);

      await tester.tap(find.text('Accepted'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('sidebar-marker-8')),
        findsOneWidget,
        reason: 'the badge counts every waiting request, not the filtered rows',
      );
    });

    testWidgets('a zero count draws nothing', (tester) async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..waiting = 0;
      await _pump(tester, repository: repository);

      expect(find.byKey(const ValueKey('sidebar-marker-8')), findsNothing);
    });

    testWidgets('a failed count is not drawn as 0', (tester) async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..countError = 'offline';
      final viewmodel = await _pump(tester, repository: repository);

      expect(viewmodel.waitingCount, isNull);
      expect(find.byKey(const ValueKey('sidebar-marker-8')), findsNothing);
    });
  });

  group('the review dialog', () {
    testWidgets('shows the context, the lines and the no-reservation copy', (
      tester,
    ) async {
      final repository = _StubRepository()..rows = [_request()];
      await _pump(tester, repository: repository);
      await _openReview(tester);

      expect(find.text('CPMS approver'), findsOneWidget);
      expect(find.text('Engr. Reyes'), findsOneWidget);
      expect(find.text('Deliver to gate 2 before noon.'), findsOneWidget);
      expect(find.text('Portland Cement'), findsOneWidget);
      expect(find.text('40 kg · 40 kg bag'), findsOneWidget);
      expect(find.text('Qty 4'), findsOneWidget);
      expect(find.text('CPMS-REQ-8842'), findsOneWidget);
      expect(
        find.text(
          'Accepting does not reserve stock. Amount owed is recorded when '
          'materials are released.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Expected amount, not yet owed'),
        findsNothing,
        reason: 'a waiting request has no expected amount to explain',
      );
    });

    testWidgets('an all-false Accept is refused with Decline as the way out', (
      tester,
    ) async {
      final repository = _StubRepository()..rows = [_request()];
      await _pump(tester, repository: repository);
      await _openReview(tester);

      await tester.tap(find.byKey(const ValueKey('line-21-not-available')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('line-21-reason')),
        'Not stocked',
      );
      await tester.tap(find.byKey(const Key('accept-request')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'At least one line must be available. Decline the whole request instead.',
        ),
        findsOneWidget,
      );
      expect(repository.acceptCalls, 0);
      expect(find.text('Decline request'), findsOneWidget);
    });

    testWidgets('a Not-available line without a reason is refused', (
      tester,
    ) async {
      final repository = _StubRepository()
        ..rows = [
          _request(
            items: [
              _line(),
              _line(id: 22, productName: 'Steel bar'),
            ],
          ),
        ];
      await _pump(tester, repository: repository);
      await _openReview(tester);

      await tester.tap(find.byKey(const ValueKey('line-21-available')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('line-22-not-available')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accept-request')));
      await tester.pumpAndSettle();

      expect(
        find.text('Give a reason for each line the store will not serve.'),
        findsOneWidget,
      );
      expect(repository.acceptCalls, 0);
    });

    testWidgets('an unanswered line is refused', (tester) async {
      final repository = _StubRepository()..rows = [_request()];
      await _pump(tester, repository: repository);
      await _openReview(tester);

      await tester.tap(find.byKey(const Key('accept-request')));
      await tester.pumpAndSettle();
      expect(find.text('Answer every line before accepting.'), findsOneWidget);
      expect(repository.acceptCalls, 0);
    });

    testWidgets('Accept confirms, names the excluded lines and sends', (
      tester,
    ) async {
      final repository = _StubRepository()
        ..rows = [
          _request(
            items: [
              _line(),
              _line(id: 22, productName: 'Steel bar'),
            ],
          ),
        ];
      await _pump(tester, repository: repository);
      await _openReview(tester);

      await tester.tap(find.byKey(const ValueKey('line-21-available')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('line-22-not-available')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('line-22-reason')),
        'Not stocked',
      );
      await tester.tap(find.byKey(const Key('accept-request')));
      await tester.pumpAndSettle();

      expect(find.text('Accept this request?'), findsOneWidget);
      expect(find.textContaining('Steel bar'), findsWidgets);
      await tester.tap(find.byKey(const Key('confirm-accept')));
      await tester.pumpAndSettle();

      expect(repository.acceptCalls, 1);
      expect(repository.lastDecisions, hasLength(2));
      expect(repository.lastDecisions!.map((d) => d.available), [true, false]);
      expect(repository.lastDecisions!.last.declineReason, 'Not stocked');
      expect(find.text('Request accepted.'), findsOneWidget);
      expect(find.text('Accept request'), findsNothing);
    });

    testWidgets('Decline needs a reason, then confirms and sends', (
      tester,
    ) async {
      final repository = _StubRepository()..rows = [_request()];
      await _pump(tester, repository: repository);
      await _openReview(tester);

      await tester.tap(find.byKey(const Key('decline-request')));
      await tester.pumpAndSettle();
      expect(
        find.text('Give a reason for declining the request.'),
        findsOneWidget,
      );
      expect(repository.lastReason, isNull);

      await tester.enterText(
        find.byKey(const Key('decline-reason')),
        'Cannot supply this request',
      );
      await tester.tap(find.byKey(const Key('decline-request')));
      await tester.pumpAndSettle();
      expect(find.text('Decline this request?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-decline')));
      await tester.pumpAndSettle();

      expect(repository.lastReason, 'Cannot supply this request');
      expect(find.text('Request declined.'), findsOneWidget);
    });

    testWidgets('a saved decision whose refresh failed says it was saved', (
      tester,
    ) async {
      final repository = _StubRepository()..rows = [_request()];
      await _pump(tester, repository: repository);
      await _openReview(tester);

      repository.listError = 'Server down.';
      await tester.tap(find.byKey(const ValueKey('line-21-available')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accept-request')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-accept')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The decision was saved, but the list could not be refreshed. '
          'Check the queue before answering again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a blocked request keeps both actions off and offers a retry', (
      tester,
    ) async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..writeError = const RequisitionServiceException(
          'Cannot connect to the BuildPro server.',
          outcomeUnknown: true,
        )
        // The refresh the timeout forces fails too: nothing can tell whether
        // the decision landed, so both actions must stay off.
        ..detailError = 'Server down.';
      await _pump(tester, repository: repository);
      await _openReview(tester);

      await tester.tap(find.byKey(const ValueKey('line-21-available')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('accept-request')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-accept')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'The decision may or may not have been saved. Retry refresh before '
          'trying again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Retry refresh'), findsOneWidget);
      final accept = tester.widget<FilledButton>(
        find.byKey(const Key('accept-request')),
      );
      expect(accept.onPressed, isNull, reason: 'both actions stay disabled');
    });

    testWidgets('the money line never shows ₱0.00 for an unknown amount', (
      tester,
    ) async {
      final repository = _StubRepository()
        ..rows = [_request(status: 'ACCEPTED', expectedAmount: null)];
      await _pump(tester, repository: repository);
      await tester.tap(find.text('Accepted'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(find.text('Expected amount unavailable'), findsOneWidget);
      expect(find.textContaining('₱0.00'), findsNothing);
    });

    testWidgets('a declined request hides the expected amount entirely', (
      tester,
    ) async {
      final repository = _StubRepository()
        ..rows = [
          _request(
            status: 'DECLINED',
            declineReason: 'Cannot supply this request',
          ),
        ];
      await _pump(tester, repository: repository);
      await tester.tap(find.text('Declined'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(
        find.text('Cannot supply this request'),
        findsOneWidget,
        reason: 'the whole-request decline reason is shown',
      );
      expect(find.text('Expected amount, not yet owed'), findsNothing);
      expect(find.text('Expected amount unavailable'), findsNothing);
    });

    testWidgets('a closed request explains abandoned quantities', (
      tester,
    ) async {
      final repository = _StubRepository()
        ..rows = [_request(status: 'CLOSED', expectedAmount: null)];
      await _pump(tester, repository: repository);
      await tester.tap(find.text('Closed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Anything not released stays closed. The actual balance is on '
          'Receivables.',
        ),
        findsOneWidget,
      );
    });
  });

  group('layout', () {
    for (final entry in const [
      ('1440', Size(1440, 900)),
      ('1100', Size(1100, 900)),
      ('760', Size(760, 900)),
    ]) {
      for (final scale in const [1.0, 1.3]) {
        testWidgets('${entry.$1} px at text scale $scale paints no overflow', (
          tester,
        ) async {
          final repository = _StubRepository()
            ..rows = [
              _request(
                items: [
                  _line(),
                  _line(
                    id: 22,
                    productName: 'Steel bar 10mm x 6m',
                    variantName: 'Deformed',
                    unit: 'length',
                  ),
                ],
              ),
            ]
            ..waiting = 2;
          await _pump(
            tester,
            repository: repository,
            size: entry.$2,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('Review'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Accept request'), findsOneWidget);
        });
      }
    }

    // QA saw "Revi" / "w" at 1100 in the Admin shell. Only the app's real faces
    // show it: the test font is twice as wide and wraps everywhere.
    testWidgets('the Review action stays on one line at 1100 px', (
      tester,
    ) async {
      // Real file reads never finish inside the test's fake clock.
      await tester.runAsync(() async {
        for (final (family, file) in const [
          ('OpenSans', 'OpenSans-Bold.ttf'),
          ('OpenSans', 'OpenSans-Regular.ttf'),
          ('Cinzel', 'Cinzel-Bold.ttf'),
        ]) {
          final bytes = await File('assets/fonts/$file').readAsBytes();
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
        }
      });
      final repository = _StubRepository()
        ..rows = [_request()]
        ..waiting = 1;
      await _pump(
        tester,
        repository: repository,
        size: const Size(1100, 900),
        adminShell: true,
        appTheme: true,
      );

      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text('Review'),
          matching: find.byType(RichText),
        ),
      );
      expect(
        paragraph.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(paragraph.size.width),
        reason: '"Review" wraps onto a second line',
      );
    });
  });
}
