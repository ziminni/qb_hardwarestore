// Z2 fix task B (B-D1): at 760 x 900 the last audit-log card is cut by the
// panel's bottom edge. The sweep could not tell whether the rest of that row was
// reachable, which decides whether it is a defect or just a scroll boundary.
//
// It is reachable: the list is a real scroll view and the last card ends flush
// with the panel once scrolled to the end. This test pins exactly that, so a
// future change to the panel cannot quietly turn the cut row into lost data.
import 'package:client/core/network/paged.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/audit_log.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/audit_log_repository.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/admin/views/audit_logs_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubRepository extends AuditLogRepository {
  _StubRepository(this.logs);

  final List<AuditLog> logs;

  @override
  Future<Paged<AuditLog>> fetchAuditLogs({int page = 1}) async =>
      Paged<AuditLog>(items: logs, total: logs.length, hasMore: false);
}

void main() {
  testWidgets('at 760 px the last audit card is reachable by scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: _admin(),
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: AuditLogsPage(repository: _StubRepository(_logs())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const ValueKey('DataPanel.cards'));
    expect(list, findsOneWidget, reason: 'a 760 px window shows cards');

    // The panel clips its rows to its own height, which is what the screenshot
    // caught. The question is whether the cut row can be brought into view.
    final viewport = tester.getRect(list);
    // The list is lazy: `ListView.builder` estimates the height of rows it has
    // not built yet, so one drag can stop a fraction short of the real end and
    // a second finds the extent grew. Scroll until the position reaches the
    // extent, which is what a reader does by hand.
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    for (var drag = 0; drag < 5; drag++) {
      await tester.drag(list, const Offset(0, -4000));
      await tester.pumpAndSettle();
      if (position.pixels >= position.maxScrollExtent) break;
    }
    expect(
      position.pixels,
      position.maxScrollExtent,
      reason: 'the list never reached its own end',
    );

    final last = find.byKey(const ValueKey('AdminAuditLogTable.row.8'));
    expect(last, findsOneWidget, reason: 'the last card never came into view');
    final row = tester.getRect(last);
    expect(row.top, greaterThanOrEqualTo(viewport.top));
    expect(
      row.bottom,
      lessThanOrEqualTo(viewport.bottom + 0.01),
      reason: 'scrolled to the end, the last card ends inside the panel',
    );
    // And its detail line - the part the screenshot showed cut - is laid out.
    expect(find.text('row 8 logged in.'), findsOneWidget);
  });
}

/// Eight entries, more than a 900 px window shows: the trail the sweep caught.
List<AuditLog> _logs() => [
  for (var id = 1; id <= 8; id++)
    AuditLog(
      id: id,
      userEmail: 'user$id@demo.ph',
      actionType: 'LOGIN',
      description: 'row $id logged in.',
      timestamp: DateTime(2026, 11, 2, 20, id),
      ipAddress: '10.0.0.$id',
    ),
];

AuthViewmodel _admin() {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth.user = User(
    id: 1,
    username: 'admin',
    email: 'admin@demo.ph',
    fullName: 'Ada Admin',
    role: const Role(id: 1, name: 'admin', displayName: 'Administrator'),
  );
  return auth;
}
