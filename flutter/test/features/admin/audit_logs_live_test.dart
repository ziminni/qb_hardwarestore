// Decision D-01 (admin-workflow): the Audit Logs screen used to render
// `AdminMockData.auditLogs` — three invented rows, in the one screen whose
// entire purpose is to be trustworthy. An audit trail that shows fake activity
// is worse than an empty one.
//
// The replacement is `AuditLogRepository` over `GET /api/v1/audit-logs/`
// (admin-only, ordered `-timestamp` server-side).
//
// Card A6 (UI refresh) changed what the table renders, so three expectations
// below were changed on purpose: the rows are now `AuditLog` objects (not the
// raw `[time, email, code, description]` strings), the action is a readable
// badge word ("Sale", not "SALE"), and the timestamp goes through
// `formatDateTime` (D6: one date format for the whole app). The failure banner
// is the shared `ErrorBanner` now, not the sales-local `LiveLoadErrorBanner`.
// What the file exists to prove is unchanged: the table is fed EXACTLY the
// repository's rows, an empty trail says so, and a failure names itself and
// retries.
//
// These tests pin:
//   * the table is fed EXACTLY the repository's rows,
//   * a load in flight shows a spinner rather than an empty table (an empty
//     audit table reads as "nothing happened"),
//   * a failure names itself and offers a retry that actually re-fetches,
//   * no logs says "No audit logs recorded." instead of a bare header.
//
// The page builds its own repository in production, so the injected seam is
// what makes these states renderable at all.

import 'package:client/core/network/paged.dart';
import 'package:client/data/models/audit_log.dart';
import 'package:client/data/repositories/audit_log_repository.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/audit_log_service.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/admin/views/audit_logs_page.dart';
import 'package:client/features/admin/widgets/admin_audit_log_table.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubAuditLogRepository extends AuditLogRepository {
  _StubAuditLogRepository({this.rows = const []});

  List<AuditLog> rows;
  String? failure;
  int calls = 0;
  int? lastPage;

  @override
  Future<Paged<AuditLog>> fetchAuditLogs({int page = 1}) async {
    calls++;
    lastPage = page;
    final failure = this.failure;
    if (failure != null) throw AuditLogServiceException(failure);
    return Paged<AuditLog>(items: rows, total: rows.length, hasMore: false);
  }
}

AuditLog _log({
  required int id,
  required String userEmail,
  required String actionType,
  required String description,
  required DateTime timestamp,
}) => AuditLog(
  id: id,
  userEmail: userEmail,
  actionType: actionType,
  description: description,
  ipAddress: '10.0.0.5',
  timestamp: timestamp,
);

Widget _app(Widget child) => ChangeNotifierProvider<AuthViewmodel>.value(
  value: AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: child),
);

void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('AuditLogsPage', () {
    testWidgets('the table is fed the live rows, not the mock ones', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(
          AuditLogsPage(
            repository: _StubAuditLogRepository(
              rows: [
                _log(
                  id: 2,
                  userEmail: 'ana.lopez@qb.local',
                  actionType: 'SALE',
                  description: 'Completed sale #S-2291',
                  timestamp: DateTime(2026, 10, 22, 14, 5),
                ),
                _log(
                  id: 1,
                  userEmail: 'ben.cruz@qb.local',
                  actionType: 'STOCK_ADJUST',
                  description: 'Adjusted PVC pipe stock by -4',
                  timestamp: DateTime(2026, 10, 22, 9, 7),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final table = tester.widget<AdminAuditLogTable>(
        find.byType(AdminAuditLogTable),
      );
      // The rows come straight from the repository: same order, same facts.
      expect(
        table.logs.map(
          (log) => [log.userEmail, log.actionType, log.description],
        ),
        [
          ['ana.lopez@qb.local', 'SALE', 'Completed sale #S-2291'],
          [
            'ben.cruz@qb.local',
            'STOCK_ADJUST',
            'Adjusted PVC pipe stock by -4',
          ],
        ],
      );

      // And the rendered cells, so the assertion is not table-shape-only.
      expect(find.text('ana.lopez@qb.local'), findsOneWidget);
      expect(find.text('ben.cruz@qb.local'), findsOneWidget);
      // Words, not the server's code (card A6).
      expect(find.text('Sale'), findsWidgets);
      expect(find.text('SALE'), findsNothing);
      // One date format (D6).
      expect(find.text('Oct 22, 2026, 2:05 PM'), findsOneWidget);

      // The old mock rows must be gone: their invented actions have no server
      // counterpart here, and a leftover row would mean mock data still feeds
      // the screen.
      expect(find.text('Signed in at POS Terminal 02'), findsNothing);
    });

    testWidgets('it loads page 1 on open', (tester) async {
      _sizeUp(tester);
      final repository = _StubAuditLogRepository(
        rows: [
          _log(
            id: 1,
            userEmail: 'ana.lopez@qb.local',
            actionType: 'LOGIN',
            description: 'Signed in',
            timestamp: DateTime(2026, 10, 22, 8, 0),
          ),
        ],
      );
      await tester.pumpWidget(_app(AuditLogsPage(repository: repository)));
      await tester.pumpAndSettle();

      expect(repository.calls, 1);
      expect(repository.lastPage, 1);
    });

    testWidgets('a load in flight shows a spinner, not an empty table', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(AuditLogsPage(repository: _StubAuditLogRepository())),
      );
      // First frame only: the fetch is triggered from a post-frame callback.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text('No audit logs recorded.'),
        findsNothing,
        reason: 'a load in flight is not an empty trail',
      );

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a failure names itself and the retry re-fetches', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _StubAuditLogRepository()
        ..failure = 'No permission to view the audit trail.';
      await tester.pumpWidget(_app(AuditLogsPage(repository: repository)));
      await tester.pumpAndSettle();

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(
        find.text('No permission to view the audit trail.'),
        findsOneWidget,
      );
      expect(
        find.text('No audit logs recorded.'),
        findsNothing,
        reason: 'a failed load must not render an empty audit trail',
      );

      repository
        ..failure = null
        ..rows = [
          _log(
            id: 3,
            userEmail: 'ana.lopez@qb.local',
            actionType: 'LOGIN',
            description: 'Signed in',
            timestamp: DateTime(2026, 10, 22, 8, 0),
          ),
        ];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(repository.calls, 2);
      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.text('ana.lopez@qb.local'), findsOneWidget);
    });

    testWidgets('no logs says so instead of showing a bare header', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(AuditLogsPage(repository: _StubAuditLogRepository())),
      );
      await tester.pumpAndSettle();

      expect(find.text('No audit logs recorded.'), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'an empty trail is not still loading',
      );
      expect(
        find.text('No audit logs match these filters.'),
        findsNothing,
        reason: 'nothing was filtered: the trail itself is empty',
      );
    });
  });
}
