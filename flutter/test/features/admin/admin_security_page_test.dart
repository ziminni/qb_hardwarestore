import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/system_admin_service.dart';
import 'package:client/features/admin/views/admin_security_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1440, 1100),
  List<ActiveSessionRecord> sessions = const [],
  List<LoginActivityRecord> events = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final auth = AuthViewmodel(AuthRepository(AuthService()))
    ..user = const User(
      id: 1,
      username: 'admin',
      email: 'admin@qbhardware.com',
      fullName: 'Ada Min',
      role: Role(id: 1, name: 'admin', displayName: 'Admin'),
      isActive: true,
    );

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: AdminSecurityPage(
          initialSessions: sessions,
          initialLoginEvents: events,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('security route is fenced to Admin only', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: AppAreas.admin,
        location: AppRoutes.adminSecurity,
      ),
      isNull,
    );
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: AppAreas.sales,
        location: AppRoutes.adminSecurity,
      ),
      AppRoutes.salesDashboard,
    );
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: AppAreas.inventory,
        location: AppRoutes.adminSecurity,
      ),
      AppRoutes.inventoryDashboard,
    );
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: AppAreas.pos,
        location: AppRoutes.adminSecurity,
      ),
      AppRoutes.posDashboard,
    );
  });

  testWidgets('renders current session and empty remote tables cleanly', (
    tester,
  ) async {
    for (final size in const [Size(1440, 1000), Size(760, 900)]) {
      await _pump(tester, size: size);
      expect(find.text('Active Sessions & Security'), findsOneWidget);
      expect(find.text('Ada Min (admin)'), findsOneWidget);
      expect(find.text('Password & session policy'), findsOneWidget);
      expect(find.text('Awaiting sessions API'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('filters active sessions & opens Force sign out confirm', (
    tester,
  ) async {
    final sessions = [
      ActiveSessionRecord(
        id: 's1',
        fullName: 'Rosa Cruz',
        username: 'rosa',
        roleLabel: 'Cashier',
        deviceLabel: 'POS Counter 1',
        ipAddress: '192.168.1.42',
        lastSeenAt: DateTime(2026, 11, 19, 10, 15),
      ),
      ActiveSessionRecord(
        id: 's2',
        fullName: 'Ben Santos',
        username: 'ben',
        roleLabel: 'Stock Manager',
        deviceLabel: 'Warehouse Tablet',
        ipAddress: '192.168.1.55',
        lastSeenAt: DateTime(2026, 11, 19, 10, 0),
      ),
    ];

    final events = [
      LoginActivityRecord(
        id: 'e1',
        username: 'rosa',
        deviceLabel: 'POS Counter 1',
        ipAddress: '192.168.1.42',
        timestamp: DateTime(2026, 11, 19, 8, 0),
        succeeded: true,
      ),
      LoginActivityRecord(
        id: 'e2',
        username: 'unknown',
        deviceLabel: 'Unknown browser',
        ipAddress: '192.168.1.99',
        timestamp: DateTime(2026, 11, 19, 9, 12),
        succeeded: false,
      ),
    ];

    await _pump(tester, sessions: sessions, events: events);

    // Filter sessions by Cashier role chip.
    final cashierChip = find.descendant(
      of: find.byType(FilterBar).first,
      matching: find.text('Cashier'),
    );
    await tester.ensureVisible(cashierChip);
    await tester.tap(cashierChip);
    await tester.pumpAndSettle();

    expect(find.text('Rosa Cruz'), findsOneWidget);
    expect(find.text('Ben Santos'), findsNothing);

    // Tap Force sign out opens confirmation dialog.
    final forceOut = find.text('Force sign out');
    await tester.ensureVisible(forceOut);
    await tester.tap(forceOut);
    await tester.pumpAndSettle();
    expect(find.text('Force sign out Rosa Cruz?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Filter login events to Failed only.
    final failedChip = find.descendant(
      of: find.byType(FilterBar).last,
      matching: find.text('Failed'),
    );
    await tester.ensureVisible(failedChip);
    await tester.tap(failedChip);
    await tester.pumpAndSettle();
    expect(find.text('unknown'), findsOneWidget);
  });

  testWidgets('syncs live sessions, policy updates, and session revocation with backend service', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final fakeService = _FakeSystemAdminService();
    final auth = AuthViewmodel(AuthRepository(AuthService()))
      ..user = const User(
        id: 1,
        username: 'admin',
        email: 'admin@qbhardware.com',
        fullName: 'Ada Min',
        role: Role(id: 1, name: 'admin', displayName: 'Admin'),
        isActive: true,
      );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: auth,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: AdminSecurityPage(service: fakeService),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Live server sync'), findsOneWidget);
    expect(find.text('Synced with server'), findsOneWidget);
    expect(find.text('Rosa Cruz'), findsOneWidget);

    // Update minimum password length policy -> syncs with backend service.
    await tester.tap(find.text('12 chars'));
    await tester.pumpAndSettle();
    expect(fakeService.lastUpdatedPolicy?.minPasswordLength, 12);

    // Confirm Force sign out -> calls revokeSession on backend service.
    final forceOut = find.text('Force sign out');
    await tester.ensureVisible(forceOut);
    await tester.tap(forceOut);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Force sign out'));
    await tester.pumpAndSettle();

    expect(fakeService.revokedSessionIds, contains('42'));
    expect(find.text('Rosa Cruz'), findsNothing);
  });
}

class _FakeSystemAdminService extends SystemAdminService {
  SecurityPolicyState? lastUpdatedPolicy;
  final List<String> revokedSessionIds = [];
  final List<ActiveSessionRecord> _sessions = [
    ActiveSessionRecord(
      id: '42',
      fullName: 'Rosa Cruz',
      username: 'rosa',
      roleLabel: 'Cashier',
      deviceLabel: 'Cashier terminal',
      ipAddress: '192.168.1.42',
      lastSeenAt: DateTime(2026, 11, 19, 10, 15),
    ),
  ];

  @override
  Future<SecurityOverviewPayload> fetchSecurityOverview() async {
    return SecurityOverviewPayload(
      policy: lastUpdatedPolicy ?? const SecurityPolicyState(),
      sessions: [..._sessions],
      loginEvents: [
        LoginActivityRecord(
          id: '101',
          username: 'rosa',
          deviceLabel: 'POS / Web client',
          ipAddress: '192.168.1.42',
          timestamp: DateTime(2026, 11, 19, 8, 0),
          succeeded: true,
        ),
      ],
    );
  }

  @override
  Future<SecurityPolicyState> updateSecurityPolicy(
    SecurityPolicyState policy,
  ) async {
    lastUpdatedPolicy = policy;
    return policy;
  }

  @override
  Future<void> revokeSession(String sessionId) async {
    revokedSessionIds.add(sessionId);
    _sessions.removeWhere((s) => s.id == sessionId);
  }
}
