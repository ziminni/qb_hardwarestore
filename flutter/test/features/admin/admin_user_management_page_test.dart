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

import 'dart:math' as math;

import 'package:client/core/theme/app_theme.dart';
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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _storeManagerRole = Role(
  id: 3,
  name: 'sales',
  displayName: 'Store Manager',
);
const _cashierRole = Role(id: 4, name: 'pos', displayName: 'Cashier');

/// The admin tier as the wire sends it: one 'admin' CODE for both Admin and
/// System Administrator groups (serializers.py maps both onto it).
const _adminRole = Role(id: 1, name: 'admin', displayName: 'Admin');

/// The other admin-tier group, as `serializers.py` sends it: the System
/// Administrator group maps onto the SAME 'admin' code as Admin, so a role-CODE
/// comparison covers both without naming either label.
const _systemAdminRole = Role(
  id: 2,
  name: 'admin',
  displayName: 'System Administrator',
);

const _adminAccount = User(
  id: 1,
  username: 'admin',
  email: 'admin@example.com',
  fullName: 'Ada Min',
  role: _adminRole,
);

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
    required List<String> roles,
  }) async => const User(
    id: 9,
    username: 'newcashier',
    email: 'new@demo.ph',
    fullName: 'New Cashier',
    role: _cashierRole,
  );
}

/// The three fixture accounts plus the Admin account, so the authority rule is
/// readable on one screen.
class _WithAdminStub extends _StubUsersService {
  @override
  Future<List<User>> fetchUsers({String? search}) async {
    return const [_adminAccount, _manager, _cashier];
  }
}

/// Both admin-tier groups in one list: Admin and System Administrator.
class _WithBothAdminGroupsStub extends _StubUsersService {
  @override
  Future<List<User>> fetchUsers({String? search}) async {
    return const [
      _adminAccount,
      User(
        id: 9,
        username: 'sysadmin',
        email: 'sysadmin@example.com',
        fullName: 'Sys Admin',
        role: _systemAdminRole,
      ),
      _cashier,
    ];
  }
}

/// Twelve working accounts: a store big enough that the list cannot fit on a
/// 760 x 900 window, which is where the wheels stopped moving (QA wave 3b).
class _TwelveAccountsStub extends _StubUsersService {
  static final List<User> rows = [
    for (var index = 1; index <= 12; index++)
      User(
        id: index,
        username: 'staff$index',
        email: 'staff$index@demo.ph',
        fullName: 'Staff $index',
        role: index.isEven ? _cashierRole : _storeManagerRole,
      ),
  ];

  @override
  Future<List<User>> fetchUsers({String? search}) async => rows;

  @override
  Future<UserStats> fetchUserStats() async =>
      const UserStats(total: 12, active: 12, inactive: 0, rolesAssigned: 2);
}

/// Counts deactivate/reactivate + role writes, and reloads after each so the
/// list comes back from the server (no local mutation).
class _ActionStub extends _StubUsersService {
  _ActionStub({this.actionFailure}) : super();

  final String? actionFailure;
  int setActiveCalls = 0;
  bool? lastActiveValue;
  int assignCalls = 0;
  List<String>? lastAssignRoles;

  @override
  Future<User> setActive({required int id, required bool isActive}) async {
    setActiveCalls++;
    lastActiveValue = isActive;
    final failure = actionFailure;
    if (failure != null) throw UsersServiceException(failure);
    return (await fetchUsers()).first;
  }

  @override
  Future<User> assignRoles({
    required int id,
    required List<String> roles,
  }) async {
    assignCalls++;
    lastAssignRoles = roles;
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
  ThemeData? theme,
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
        theme: theme,
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

/// WCAG contrast of two opaque colours, the arithmetic the browser uses.
///
/// The same check as `test/shared/widgets/app_dialog_test.dart`; repeated here
/// so the two files do not import each other's helpers.
double _contrastOf(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// One account row or card, by the key the table gives it.
Finder _row(int userId) => find.byKey(ValueKey('admin.user.$userId'));

/// The search field inside the filter bar.
Finder get _searchField => find.descendant(
  of: find.byType(FilterBar),
  matching: find.byType(TextField),
);

/// Any row action inside [userId]'s row.
Finder _rowActions(int userId) =>
    find.descendant(of: _row(userId), matching: find.byType(TextButton));

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

  testWidgets('every account is reachable by scrolling at 760 x 900', (
    tester,
  ) async {
    // FX7 (QA wave 3b): two cards fit, the rest could not be reached: the wheel
    // and PageDown moved nothing. A list that builds lazily must still scroll.
    await _pump(
      tester,
      size: const Size(760, 900),
      viewmodel: AdminUsersViewmodel(users: _TwelveAccountsStub()),
    );

    final lastRow = _row(12);
    expect(
      lastRow,
      findsNothing,
      reason: 'a lazy list has not built the twelfth account yet',
    );

    await tester.scrollUntilVisible(
      lastRow,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('DataPanel.cards')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find
          .descendant(
            of: lastRow,
            matching: find.widgetWithText(TextButton, 'Change role'),
          )
          .hitTestable(),
      findsOneWidget,
      reason: "the last account's action must be tappable",
    );
  });

  testWidgets('a wheel outside the list still moves the list at 760 x 900', (
    tester,
  ) async {
    // FX7 (QA wave 3b): the reported gesture was the WHEEL, and it moved
    // nothing. The list scrolls under its own pointer (the two tests above),
    // but the page has no scroll view of its own — the summary, the search
    // field and the wrapped chip rows hold the top third of a 760 x 900 window
    // — so a wheel there hit no scrollable at all and the remaining accounts
    // were unreachable until the pointer found the list.
    await _pump(
      tester,
      size: const Size(760, 900),
      viewmodel: AdminUsersViewmodel(users: _TwelveAccountsStub()),
    );

    final lastAction = find.descendant(
      of: _row(12),
      matching: find.widgetWithText(TextButton, 'Change role'),
    );
    expect(lastAction.hitTestable(), findsNothing);

    // Over the filter chips: the part of the page with no scroll view.
    final point = tester.getCenter(
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('All roles'),
      ),
    );
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: point);
    addTearDown(gesture.removePointer);
    for (var i = 0; i < 10; i++) {
      await tester.sendEventToBinding(
        PointerScrollEvent(position: point, scrollDelta: const Offset(0, 300)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(
      lastAction.hitTestable(),
      findsOneWidget,
      reason: "the wheel must reach the last account's action from anywhere",
    );
  });

  testWidgets('every account is reachable by scrolling at 1366 x 768', (
    tester,
  ) async {
    await _pump(
      tester,
      size: const Size(1366, 768),
      viewmodel: AdminUsersViewmodel(users: _TwelveAccountsStub()),
    );

    final lastRow = _row(12);
    await tester.scrollUntilVisible(
      lastRow,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('DataPanel.table')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find
          .descendant(
            of: lastRow,
            matching: find.widgetWithText(TextButton, 'Change role'),
          )
          .hitTestable(),
      findsOneWidget,
    );
  });

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

  // ------------------------------------------------- authority on admin rows

  testWidgets('a Store Manager gets no row actions on an admin account', (
    tester,
  ) async {
    // FX3: the server refuses these with 403 USER_ADMIN_FORBIDDEN, so offering
    // them is a dead control. The rule is the role CODE ('admin'), the same
    // comparison the shell and the role picker use.
    await _pump(
      tester,
      roleCode: 'sales',
      roleLabel: 'Store Manager',
      viewmodel: AdminUsersViewmodel(users: _WithAdminStub()),
    );

    expect(
      _rowActions(1),
      findsNothing,
      reason: 'no Deactivate or Change role on the Admin row',
    );
    // The working account is still manageable.
    expect(
      find.descendant(
        of: _row(4),
        matching: find.widgetWithText(TextButton, 'Change role'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row(4),
        matching: find.widgetWithText(TextButton, 'Deactivate'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'a System Administrator account is an admin account for a manager too',
    (tester) async {
      // The two admin groups have different LABELS and one CODE. The authority
      // rule reads the code, so the System Administrator row is protected
      // without the client knowing its label at all.
      await _pump(
        tester,
        roleCode: 'sales',
        roleLabel: 'Store Manager',
        viewmodel: AdminUsersViewmodel(users: _WithBothAdminGroupsStub()),
      );

      expect(_rowActions(1), findsNothing, reason: 'Admin has no actions');
      expect(
        _rowActions(9),
        findsNothing,
        reason: 'System Administrator has no actions either',
      );
      expect(
        find.descendant(
          of: _row(4),
          matching: find.widgetWithText(TextButton, 'Change role'),
        ),
        findsOneWidget,
        reason: 'a cashier is still manageable',
      );
    },
  );

  testWidgets('an Admin gets row actions on every account, admin included', (
    tester,
  ) async {
    await _pump(
      tester,
      viewmodel: AdminUsersViewmodel(users: _WithAdminStub()),
    );

    expect(
      find.descendant(
        of: _row(1),
        matching: find.widgetWithText(TextButton, 'Change role'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row(1),
        matching: find.widgetWithText(TextButton, 'Deactivate'),
      ),
      findsOneWidget,
    );
  });

  // ---------------------------------------------------------- clear filters

  testWidgets('a search that hides rows offers Clear filters', (tester) async {
    // FX5: the summary line keeps saying "12 accounts" while three rows are on
    // screen, so a reader needs one obvious way back to the whole list.
    await _pump(tester);

    expect(
      find.text('Clear filters'),
      findsNothing,
      reason: 'nothing is filtered yet',
    );

    await tester.enterText(_searchField, 'zzz');
    await tester.pumpAndSettle();

    expect(find.text('No accounts match these filters.'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Clear filters'));
    await tester.pumpAndSettle();

    expect(find.text('Mana Ger'), findsWidgets);
    expect(find.text('Clear filters'), findsNothing);
    expect(
      tester.widget<TextField>(_searchField).controller?.text,
      isEmpty,
      reason: 'the field is cleared with the rows',
    );
  });

  testWidgets('Clear filters also drops the chip filters', (tester) async {
    await _pump(tester);

    await tester.tap(_chip('Cashier'));
    await tester.pumpAndSettle();
    expect(find.text('Mana Ger'), findsNothing);

    await tester.tap(find.widgetWithText(TextButton, 'Clear filters'));
    await tester.pumpAndSettle();

    expect(find.text('Mana Ger'), findsWidgets);
    expect(find.text('Clear filters'), findsNothing);
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

  testWidgets('change role offers roles, never admin to a manager', (
    tester,
  ) async {
    await _pump(tester, roleCode: 'sales', roleLabel: 'Store Manager');

    await tester.tap(find.text('Change role').first);
    await tester.pumpAndSettle();

    // Multi-select chips keyed by code: the server's word for each role.
    expect(find.text('Cashier'), findsWidgets);
    expect(find.text('Stock Manager'), findsWidgets);
    expect(find.text('Admin'), findsNothing);
    expect(find.text('System Administrator'), findsNothing);
  });

  testWidgets('the selected role chip label is readable on its gold fill', (
    tester,
  ) async {
    // The real theme: the chip colours (and the black pill this test forbids)
    // come from `chipTheme`, not from the dialog.
    await _pump(tester, theme: AppTheme.lightTheme);

    await tester.tap(find.text('Change role').first);
    await tester.pumpAndSettle();

    // The manager row holds Store Manager, so that chip starts selected.
    final chipFinder = find.widgetWithText(FilterChip, 'Store Manager');
    final chip = tester.widget<FilterChip>(chipFinder);
    expect(chip.selected, isTrue);

    // The fill the chip really paints, and the ink the paragraph really
    // resolved: WCAG AA for the label the person has to read.
    final chipTheme = ChipTheme.of(tester.element(chipFinder));
    final fill = chip.selectedColor ?? chipTheme.selectedColor!;
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: chipFinder, matching: find.text('Store Manager')),
    );
    final ink = paragraph.text.style!.color!;

    expect(
      _contrastOf(ink, fill),
      greaterThanOrEqualTo(4.5),
      reason: 'a selected role chip must be readable, not dark-on-dark',
    );
  });

  testWidgets('change role assigns the picked roles, then reloads', (
    tester,
  ) async {
    final service = _ActionStub();
    await _pump(tester, viewmodel: AdminUsersViewmodel(users: service));
    final readsBefore = service.fetchCalls;

    await tester.tap(find.text('Change role').first);
    await tester.pumpAndSettle();
    // The row is a Store Manager; add Cashier beside it.
    await tester.tap(find.widgetWithText(FilterChip, 'Cashier'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Save roles'));
    await tester.pumpAndSettle();

    expect(service.assignCalls, 1);
    expect(
      service.lastAssignRoles,
      containsAll(['sales', 'pos']),
      reason: 'roles[] is a full replacement of what the account holds',
    );
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
