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
        id: 2, username: 'manager', email: 'm@demo.ph', fullName: 'Mana Ger',
        role: Role(id: 3, name: 'sales', displayName: 'Store Manager'),
      ),
    ];
  }

  @override
  Future<UserStats> fetchUserStats() async => const UserStats(
    total: 5,
    active: 4,
    inactive: 1,
    rolesAssigned: 3,
  );

  @override
  Future<User> createUser({
    required String username,
    required String email,
    required String fullName,
    required String password,
    required String groupName,
  }) async => const User(
    id: 9, username: 'newcashier', email: 'new@demo.ph',
    fullName: 'New Cashier',
    role: Role(id: 4, name: 'pos', displayName: 'Cashier'),
  );
}

Future<void> _pump(WidgetTester tester, {String? failure}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        home: AdminUserManagementPage(
          viewmodel: AdminUsersViewmodel(
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

  testWidgets('create opens a dialog with the mandatory role', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Cashier'), findsWidgets);
  });
}
