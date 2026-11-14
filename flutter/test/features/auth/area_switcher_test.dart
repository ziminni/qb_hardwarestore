// Phase 4 F3b: the area picker and the header switcher.
//
// The picker offers ONLY the areas the server assigned, in the server's order;
// it is never a staff picker and never a way to reach an area the account does
// not hold. The header switcher appears only for an account with more than one
// area.

import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/active_area_store.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/area_picker_page.dart';
import 'package:client/features/auth/widget/area_switcher_menu.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _admin = Role(id: 1, name: 'admin', displayName: 'Admin');
const _pos = Role(id: 4, name: 'pos', displayName: 'Cashier');

User _account(List<Role> roles) => User(
  id: 5,
  username: 'staff5',
  email: 'staff5@demo.ph',
  fullName: 'Staff Five',
  role: roles.isEmpty ? null : roles.first,
  roles: roles,
);

Future<AuthViewmodel> _pumpPage(
  WidgetTester tester, {
  required List<Role> roles,
  Widget? child,
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final auth = AuthViewmodel(
    _PickerRepository(_account(roles)),
    areas: const ActiveAreaStore(),
  );
  await auth.login('staff5', 'demo1234');

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: child ?? const AreaPickerPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the picker offers only the assigned areas', (tester) async {
    await _pumpPage(tester, roles: [_admin, _pos]);

    expect(find.text('Choose your area'), findsOneWidget);
    expect(find.text('Admin'), findsWidgets);
    expect(find.text('Cashier'), findsWidgets);
    expect(find.text('Store Manager'), findsNothing);
    expect(find.text('Stock Manager'), findsNothing);
  });

  testWidgets('picking an area makes it the active area', (tester) async {
    final auth = await _pumpPage(tester, roles: [_admin, _pos]);

    await tester.tap(find.widgetWithText(FilledButton, 'Cashier'));
    await tester.pumpAndSettle();

    expect(auth.activeArea, 'pos');
    expect(auth.needsAreaChoice, isFalse);
  });

  testWidgets('the first area takes keyboard focus, and Enter picks it', (
    tester,
  ) async {
    final auth = await _pumpPage(tester, roles: [_admin, _pos]);

    expect(
      FocusManager.instance.primaryFocus,
      isNotNull,
      reason: 'a keyboard user starts inside the card, not on a dead surface',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(
      auth.activeArea,
      'admin',
      reason: 'the focused control is the first assigned area',
    );
  });

  testWidgets('a single-area account never sees the picker list', (
    tester,
  ) async {
    await _pumpPage(tester, roles: [_pos]);

    // Routed away by the redirect in the real app; reached directly it still
    // offers only the one area and no dead choices.
    expect(find.text('Admin'), findsNothing);
    expect(find.text('Cashier'), findsWidgets);
  });

  testWidgets('the header switcher is absent for a single-area account', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      roles: [_pos],
      child: const Scaffold(body: AreaSwitcherMenu()),
    );

    expect(find.byTooltip('Switch area'), findsNothing);
  });

  testWidgets('the header switcher lists every area for multi-role staff', (
    tester,
  ) async {
    final auth = await _pumpPage(
      tester,
      roles: [_admin, _pos],
      child: const Scaffold(body: AreaSwitcherMenu()),
    );
    await auth.selectArea('admin');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Switch area'));
    await tester.pumpAndSettle();

    expect(find.text('Cashier'), findsWidgets);
    await tester.tap(find.text('Cashier').last);
    await tester.pumpAndSettle();

    expect(auth.activeArea, 'pos');
  });
}

class _PickerRepository extends AuthRepository {
  _PickerRepository(this.account) : super(_PickerAuthService());

  final User account;

  @override
  Future<User?> restoreSession() async => account;

  @override
  Future<User> login(String identifier, String password) async => account;

  @override
  Future<void> logout() async {}
}

class _PickerAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async {
    throw const AuthException('not used in these tests');
  }

  @override
  Future<void> logout() async {}
}
