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

class _StubUsersService extends UserService {
  _StubUsersService({this.failure}) : super();

  final String? failure;

  @override
  Future<List<User>> fetchUsers({String? search}) async {
    final failure = this.failure;
    if (failure != null) throw UsersServiceException(failure);
    return const [
      User(
        id: 2,
        username: 'manager',
        email: 'm@demo.ph',
        fullName: 'Mana Ger',
        role: Role(id: 3, name: 'sales', displayName: 'Store Manager'),
      ),
    ];
  }

  @override
  Future<UserStats> fetchUserStats() async =>
      const UserStats(total: 5, active: 4, inactive: 1, rolesAssigned: 3);

  @override
  Future<User> createUser({
    required String username,
    required String email,
    required String fullName,
    required String password,
    required String groupName,
  }) async => const User(
    id: 9,
    username: 'newcashier',
    email: 'new@demo.ph',
    fullName: 'New Cashier',
    role: Role(id: 4, name: 'pos', displayName: 'Cashier'),
  );
}

/// Counts deactivate/reactivate + role writes for the action tests.
class _ActionStub extends UserService {
  _ActionStub() : super();

  int setActiveCalls = 0;
  bool? lastActiveValue;
  int assignCalls = 0;
  String? lastAssignGroup;

  @override
  Future<List<User>> fetchUsers({String? search}) async => const [
    User(
      id: 2,
      username: 'manager',
      email: 'm@demo.ph',
      fullName: 'Mana Ger',
      role: Role(id: 3, name: 'sales', displayName: 'Store Manager'),
    ),
  ];

  @override
  Future<UserStats> fetchUserStats() async =>
      const UserStats(total: 5, active: 4, inactive: 1, rolesAssigned: 3);

  @override
  Future<User> setActive({required int id, required bool isActive}) async {
    setActiveCalls++;
    lastActiveValue = isActive;
    return (await fetchUsers()).single;
  }

  @override
  Future<User> assignRole({required int id, required String groupName}) async {
    assignCalls++;
    lastAssignGroup = groupName;
    return (await fetchUsers()).single;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  String? failure,
  String roleCode = 'admin',
  String roleLabel = 'Admin',
  AdminUsersViewmodel? viewmodel,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = AuthViewmodel(AuthRepository(AuthService()))
    ..user = User(
      id: 1,
      username: 'admin',
      email: 'admin@example.com',
      fullName: 'Admin User',
      role: Role(id: 1, name: roleCode, displayName: roleLabel),
      isActive: true,
    );

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(
        home: AdminUserManagementPage(
          viewmodel:
              viewmodel ??
              AdminUsersViewmodel(
                users: _StubUsersService(failure: failure),
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a failed load shows the error with a retry', (tester) async {
    await _pump(tester, failure: 'Cannot connect to the BuildPro server.');

    expect(find.textContaining('Cannot connect'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('live rows render server users, never mock fixtures', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('Mana Ger'), findsWidgets);
    expect(find.text('24'), findsNothing);
    expect(find.text('System Administrator'), findsNothing);
  });

  testWidgets('typed search text survives setting a role filter', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('userSearchField')), 'mana');

    await tester.tap(find.text('All roles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Store Manager').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('userSearchField')))
          .controller!
          .text,
      'mana',
    );
  });

  testWidgets('create opens a dialog with the mandatory role', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Cashier'), findsWidgets);
  });

  // Phase 5 Task 2: per-row deactivate/reactivate + role change, with Create
  // hidden from the Store Manager (creation stays Admin-only server-side).
  testWidgets('an admin sees Create plus per-row actions', (tester) async {
    await _pump(tester);

    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);
    expect(find.text('Change role'), findsOneWidget);
  });

  testWidgets('a store manager gets actions but no Create button', (
    tester,
  ) async {
    await _pump(tester, roleCode: 'sales', roleLabel: 'Store Manager');

    expect(find.text('Create account'), findsNothing);
    expect(find.text('Deactivate'), findsOneWidget);
    expect(find.text('Change role'), findsOneWidget);
  });

  testWidgets('deactivate asks first, then flips through the viewmodel', (
    tester,
  ) async {
    final service = _ActionStub();
    await _pump(
      tester,
      viewmodel: AdminUsersViewmodel(users: service),
    );

    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    // The confirm sheet names the account; nothing is written yet.
    expect(find.textContaining('Deactivate Mana'), findsOneWidget);
    expect(service.setActiveCalls, 0);

    // The dialog sits on top: its confirm is the last matching button.
    await tester.tap(find.widgetWithText(TextButton, 'Deactivate').last);
    await tester.pumpAndSettle();

    expect(service.setActiveCalls, 1);
    expect(service.lastActiveValue, isFalse);
  });

  testWidgets('change role offers groups, never admin labels to a manager', (
    tester,
  ) async {
    await _pump(tester, roleCode: 'sales', roleLabel: 'Store Manager');

    await tester.tap(find.text('Change role'));
    await tester.pumpAndSettle();
    // Open the group picker: menu items render only once expanded.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('Cashier'), findsWidgets);
    expect(find.text('Admin'), findsNothing);
    expect(find.text('System Administrator'), findsNothing);
  });
}
