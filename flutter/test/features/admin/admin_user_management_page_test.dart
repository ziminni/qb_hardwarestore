// Card A2 — User management (admin `/admin/users`, Store Manager
// `/sales/staff`).
//
// The list screens were converted to `FilterBar` + `DataPanel`: four metric
// cards became one summary line, and the row actions moved INTO the row so a
// 760 px window (where `DataPanel` shows cards) still shows them instead of
// clipping them off the end of a horizontally scrolling `DataTable`.
//
// Authority is unchanged (Phase 5): an Admin sees Create account,
// Deactivate/Reactivate and Change role; a Store Manager sees the two row
// actions but no Create account, and the server still refuses admin-bound
// changes (403 `USER_ADMIN_FORBIDDEN`) and the last-admin strip (400
// `LAST_ADMIN`).

import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/user_service.dart';
import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:client/features/admin/views/admin_user_management_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _storeManagerRole = Role(
  id: 3,
  name: 'sales',
  displayName: 'Store Manager',
);
const _cashierRole = Role(id: 4, name: 'pos', displayName: 'Cashier');

const _manager = User(
  id: 2,
  username: 'manager',
  email: 'm@demo.ph',
  fullName: 'Mana Ger',
  role: _storeManagerRole,
);
const _cashier = User(
  id: 4,
  username: 'cashier',
  email: 'cashier@demo.ph',
  fullName: 'Rosa Cruz',
  role: _cashierRole,
);
const _retired = User(
  id: 5,
  username: 'ben.old',
  email: 'ben.old@demo.ph',
  fullName: 'Ben Old',
  role: _cashierRole,
  isActive: false,
);

/// The account totals the server reports for the fixture rows below: the
/// summary line must say twelve accounts while only three are on screen, which
/// is exactly the fact the old four metric cards carried.
const _stats = UserStats(total: 12, active: 10, inactive: 2, rolesAssigned: 3);

/// Loads the three fixture accounts; counts the reads so a test can prove a
/// write ends in a fresh server read instead of a local edit.
class _StubUsersService extends UserService {
  _StubUsersService({this.failure, this.failAfterFirstLoad = false}) : super();

  final String? failure;
  final bool failAfterFirstLoad;

  int fetchCalls = 0;

  @override
  Future<List<User>> fetchUsers({String? search}) async {
    fetchCalls++;
    final failure = this.failure;
    if (failure != null && (!failAfterFirstLoad || fetchCalls > 1)) {
      throw UsersServiceException(failure);
    }
    return const [_manager, _cashier, _retired];
  }

  @override
  Future<UserStats> fetchUserStats() async {
    final failure = this.failure;
    if (failure != null && (!failAfterFirstLoad || fetchCalls > 1)) {
      throw UsersServiceException(failure);
    }
    return _stats;
  }

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
    role: _cashierRole,
  );
}

/// Counts deactivate/reactivate + role writes, and reloads after each so the
/// list comes back from the server (no local mutation).
class _ActionStub extends _StubUsersService {
  _ActionStub({this.actionFailure}) : super();

  final String? actionFailure;
  int setActiveCalls = 0;
  bool? lastActiveValue;
  int assignCalls = 0;
  String? lastAssignGroup;

  @override
  Future<User> setActive({required int id, required bool isActive}) async {
    setActiveCalls++;
    lastActiveValue = isActive;
    final failure = actionFailure;
    if (failure != null) throw UsersServiceException(failure);
    return (await fetchUsers()).first;
  }

  @override
  Future<User> assignRole({required int id, required String groupName}) async {
    assignCalls++;
    lastAssignGroup = groupName;
    final failure = actionFailure;
    if (failure != null) throw UsersServiceException(failure);
    return (await fetchUsers()).first;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(1600, 1400),
  String? failure,
  bool failAfterFirstLoad = false,
  bool inSalesShell = false,
  String roleCode = 'admin',
  String roleLabel = 'Admin',
  AdminUsersViewmodel? viewmodel,
}) async {
  tester.view.physicalSize = size;
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
          inSalesShell: inSalesShell,
          viewmodel:
              viewmodel ??
              AdminUsersViewmodel(
                users: _StubUsersService(
                  failure: failure,
                  failAfterFirstLoad: failAfterFirstLoad,
                ),
              ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A chip inside the filter bar. The row badges use the same words, so a bare
/// `find.text` would hit both.
Finder _chip(String label) =>
    find.descendant(of: find.byType(FilterBar), matching: find.text(label));

void main() {
  // ---------------------------------------------------------------- summary

  testWidgets('one summary line replaces the four metric cards', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('12 accounts, 10 active, 2 inactive'), findsOneWidget);
    expect(find.text('Total accounts'), findsNothing);
    expect(find.text('Active accounts'), findsNothing);
    expect(find.text('Inactive accounts'), findsNothing);
    expect(find.text('Roles assigned'), findsNothing);
  });

  // --------------------------------------------------------------- narrow

  testWidgets('row actions stay reachable at 760 px', (tester) async {
    await _pump(tester, size: const Size(760, 900));

    // Cards, not a sideways-scrolling table: the panel decides on its own
    // content width.
    expect(find.byKey(const ValueKey('DataPanel.cards')), findsOneWidget);
    // Reachable means tappable, not merely present in the widget tree: the old
    // DataTable built every cell and clipped the actions off the window.
    expect(find.text('Deactivate').hitTestable(), findsWidgets);
    expect(find.text('Change role').hitTestable(), findsWidgets);
  });

  // ------------------------------------------------------------- both shells

  testWidgets('the admin shell and the Store Manager shell show one list', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('User Management'), findsOneWidget);
    expect(find.text('12 accounts, 10 active, 2 inactive'), findsOneWidget);
    expect(find.text('Mana Ger'), findsWidgets);

    await _pump(
      tester,
      inSalesShell: true,
      roleCode: 'sales',
      roleLabel: 'Store Manager',
    );
    // "Staff" is the shell's page title and its sidebar item; "User
    // Management" belongs to the admin sidebar only.
    expect(find.text('Staff'), findsWidgets);
    expect(find.text('User Management'), findsNothing);
    expect(find.text('12 accounts, 10 active, 2 inactive'), findsOneWidget);
    expect(find.text('Mana Ger'), findsWidgets);
    expect(find.text('Deactivate'), findsWidgets);
    expect(find.text('Change role'), findsWidgets);
    // Creation stays Admin-only server-side, so the manager is not offered it.
    expect(find.text('Create account'), findsNothing);
  });

  // ---------------------------------------------------------------- filters

  testWidgets('role chips narrow the loaded rows', (tester) async {
    await _pump(tester);

    await tester.tap(_chip('Store Manager'));
    await tester.pumpAndSettle();

    expect(find.text('Rosa Cruz'), findsNothing);
    expect(find.text('Mana Ger'), findsWidgets);
  });

  testWidgets('status chips narrow the loaded rows', (tester) async {
    await _pump(tester);

    await tester.tap(_chip('Inactive'));
    await tester.pumpAndSettle();

    expect(find.text('Rosa Cruz'), findsNothing);
    expect(find.text('Ben Old'), findsOneWidget);
  });

  testWidgets('typing narrows the list without a server round trip', (
    tester,
  ) async {
    final service = _StubUsersService();
    await _pump(tester, viewmodel: AdminUsersViewmodel(users: service));
    final readsBefore = service.fetchCalls;

    await tester.enterText(find.byType(TextField), 'rosa');
    await tester.pumpAndSettle();

    expect(find.text('Rosa Cruz'), findsOneWidget);
    expect(find.text('Mana Ger'), findsNothing);
    expect(service.fetchCalls, readsBefore);
  });

  testWidgets('a filter with no match says so, and is not the empty system', (
    tester,
  ) async {
    await _pump(tester);

    await tester.enterText(find.byType(TextField), 'nobody here');
    await tester.pumpAndSettle();

    expect(find.text('No accounts match these filters.'), findsOneWidget);
    expect(find.text('No staff accounts yet.'), findsNothing);
  });

  testWidgets('typed search text survives setting a role chip', (tester) async {
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'mana');
    await tester.pumpAndSettle();

    await tester.tap(_chip('Store Manager'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'mana',
    );
  });

  // ----------------------------------------------------------------- errors

  testWidgets('a failed first load is one banner and no summary', (
    tester,
  ) async {
    await _pump(tester, failure: 'Cannot connect to the BuildPro server.');

    expect(find.textContaining('Cannot connect'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    // A zero summary would read as "this store has no staff accounts", which is
    // a different and far more dangerous sentence than "this did not load".
    expect(find.textContaining('accounts,'), findsNothing);
  });

  testWidgets('a failed refresh keeps the rows under the banner', (
    tester,
  ) async {
    final viewmodel = AdminUsersViewmodel(
      users: _StubUsersService(
        failure: 'The staff list could not be loaded.',
        failAfterFirstLoad: true,
      ),
    );
    await _pump(tester, viewmodel: viewmodel);
    expect(find.text('Mana Ger'), findsWidgets);

    // A refresh that fails: the rows on screen are still the server's truth, so
    // they stay and the banner says why.
    await viewmodel.load();
    await tester.pumpAndSettle();

    expect(find.text('The staff list could not be loaded.'), findsOneWidget);
    expect(find.text('Mana Ger'), findsWidgets);
  });

  testWidgets('a refused deactivate surfaces the server sentence', (
    tester,
  ) async {
    final service = _ActionStub(
      actionFailure: 'Only an Admin may change that account.',
    );
    await _pump(tester, viewmodel: AdminUsersViewmodel(users: service));

    await tester.tap(find.text('Deactivate').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Deactivate').last);
    await tester.pumpAndSettle();

    expect(find.text('Only an Admin may change that account.'), findsOneWidget);
  });

  testWidgets('the last admin strip is surfaced in the banner', (tester) async {
    final service = _ActionStub(
      actionFailure: 'The last active Admin cannot be deactivated.',
    );
    await _pump(tester, viewmodel: AdminUsersViewmodel(users: service));

    await tester.tap(find.text('Deactivate').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Deactivate').last);
    await tester.pumpAndSettle();

    expect(
      find.text('The last active Admin cannot be deactivated.'),
      findsOneWidget,
    );
  });

  // ------------------------------------------------------------- authority

  testWidgets('live rows render server users, never mock fixtures', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.textContaining('Mana Ger'), findsWidgets);
    expect(find.text('24'), findsNothing);
    expect(find.text('System Administrator'), findsNothing);
  });

  testWidgets('an admin sees Create plus per-row actions', (tester) async {
    await _pump(tester);

    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Deactivate'), findsWidgets);
    expect(find.text('Change role'), findsWidgets);
  });

  testWidgets('deactivate names the account, then reloads from the server', (
    tester,
  ) async {
    final service = _ActionStub();
    await _pump(tester, viewmodel: AdminUsersViewmodel(users: service));
    final readsBefore = service.fetchCalls;

    await tester.tap(find.text('Deactivate').first);
    await tester.pumpAndSettle();
    // The confirm names the account; nothing is written yet.
    expect(find.textContaining('Deactivate Mana'), findsOneWidget);
    expect(service.setActiveCalls, 0);

    // The dialog sits on top: its confirm is the last matching button.
    await tester.tap(find.widgetWithText(TextButton, 'Deactivate').last);
    await tester.pumpAndSettle();

    expect(service.setActiveCalls, 1);
    expect(service.lastActiveValue, isFalse);
    // The row comes back from the server, not from a local guess.
    expect(service.fetchCalls, greaterThan(readsBefore));
  });

  // ---------------------------------------------------------- account form

  testWidgets('create opens a dialog with the mandatory role', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Cashier'), findsWidgets);
  });

  testWidgets('change role offers groups, never admin labels to a manager', (
    tester,
  ) async {
    await _pump(tester, roleCode: 'sales', roleLabel: 'Store Manager');

    await tester.tap(find.text('Change role').first);
    await tester.pumpAndSettle();
    // Open the group picker: menu items render only once expanded.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();

    expect(find.text('Cashier'), findsWidgets);
    expect(find.text('Admin'), findsNothing);
    expect(find.text('System Administrator'), findsNothing);
  });

  testWidgets('change role assigns the picked group, then reloads', (
    tester,
  ) async {
    final service = _ActionStub();
    await _pump(tester, viewmodel: AdminUsersViewmodel(users: service));
    final readsBefore = service.fetchCalls;

    await tester.tap(find.text('Change role').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock Manager').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Change role').last);
    await tester.pumpAndSettle();

    expect(service.assignCalls, 1);
    expect(service.lastAssignGroup, 'Stock Manager');
    expect(service.fetchCalls, greaterThan(readsBefore));
  });

  // ------------------------------------------------------------ row layout

  testWidgets('the account cell carries the name, username and email', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Mana Ger'), findsOneWidget);
    expect(find.text('manager · m@demo.ph'), findsOneWidget);
    expect(find.text('MG'), findsOneWidget);
  });

  testWidgets('a deactivated row is badged, not just worded', (tester) async {
    await _pump(tester);

    expect(
      find.descendant(
        of: find.byType(DataPanel<User>),
        matching: find.text('Inactive'),
      ),
      findsOneWidget,
    );
  });
}
