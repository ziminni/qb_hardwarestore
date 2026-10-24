// Phase 3 Task 0 (U) — the live staff list, with a groupless account in it.
//
// The failure this pins: `GET /api/v1/users/` returns `role: null` for an
// account with no group (Django superuser, or an account whose group was
// removed), `User.fromJson` threw `FormatException('Missing required object
// field "role"')`, and the WHOLE User Management list died with
// "The staff list could not be read: Missing required object field "role"".
//
// The list must render every row, the groupless one must say "No role" instead
// of showing a blank cell, and the role filter must be able to select those
// accounts — that is how an admin finds them to fix.

import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/user_service.dart';
import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:client/features/admin/views/admin_user_management_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _manager = User(
  id: 2,
  username: 'manager',
  email: 'm@demo.ph',
  fullName: 'Mana Ger',
  role: Role(id: 3, name: 'sales', displayName: 'Store Manager'),
);

/// The row the backend really sends for a superuser: `role` is JSON null.
final User _groupless = User.fromJson({
  'id': 1,
  'username': 'root',
  'email': 'root@demo.ph',
  'full_name': 'Root Operator',
  'is_active': true,
  'is_staff': true,
  'role': null,
});

class _StubUsersService extends UserService {
  _StubUsersService() : super();

  @override
  Future<List<User>> fetchUsers({String? search}) async => [
    _groupless,
    _manager,
  ];

  @override
  Future<UserStats> fetchUserStats() async =>
      const UserStats(total: 2, active: 2, inactive: 0, rolesAssigned: 1);
}

Future<void> _pumpPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        home: AdminUserManagementPage(
          viewmodel: AdminUsersViewmodel(users: _StubUsersService()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('the groupless row does not fail the parse', () {
    expect(_groupless.role, isNull);
  });

  group('viewmodel', () {
    late AdminUsersViewmodel viewmodel;

    setUp(() => viewmodel = AdminUsersViewmodel(users: _StubUsersService()));

    test('loads every row, role-less included', () async {
      await viewmodel.load();

      expect(viewmodel.loadError, isNull);
      expect(viewmodel.users, hasLength(2));
      expect(viewmodel.users.where((user) => user.role == null), hasLength(1));
    });

    test('offers "No role" as a filter value', () async {
      await viewmodel.load();

      expect(viewmodel.availableRoles, contains(User.noRoleLabel));
      expect(viewmodel.availableRoles, contains('Store Manager'));
    });

    test(
      'filtering by "No role" isolates the accounts an admin must fix',
      () async {
        await viewmodel.load();

        viewmodel.setRoleFilter(User.noRoleLabel);

        expect(viewmodel.users.single.username, 'root');
      },
    );

    test('filtering by a real role excludes the role-less account', () async {
      await viewmodel.load();

      viewmodel.setRoleFilter('Store Manager');

      expect(viewmodel.users.single.username, 'manager');
    });
  });

  group('page', () {
    testWidgets('renders both rows and badges the role-less one "No role"', (
      tester,
    ) async {
      await _pumpPage(tester);

      expect(find.text('Root Operator'), findsOneWidget);
      expect(find.text('Mana Ger'), findsOneWidget);
      expect(find.text('No role'), findsOneWidget);
      expect(find.text('Store Manager'), findsOneWidget);
      expect(
        find.textContaining('Missing required object field'),
        findsNothing,
      );
    });

    testWidgets('the role filter can pick the role-less accounts', (
      tester,
    ) async {
      await _pumpPage(tester);

      await tester.tap(find.text('All roles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No role').last);
      await tester.pumpAndSettle();

      expect(find.text('Root Operator'), findsOneWidget);
      expect(find.text('Mana Ger'), findsNothing);
    });
  });
}
