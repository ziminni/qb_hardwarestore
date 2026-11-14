// Phase 4 F3b + Phase 2 F3: which area a signed-in account works in.
//
// The server owns the ASSIGNMENT (`roles[]`); the app owns only the CHOICE of
// active area, remembered per account on this device. The choice is validated
// against the assignment every time it is restored, so a revoked role, a stale
// device preference or the previous user's pick can never open a screen.
//
// Phase 2 F3 (decision 24): an account holding SEVERAL areas is no longer
// asked to pick one. It works from the combined sidebar, so it never needs a
// picker, never has one active area, and ignores the remembered area; its
// ACTIONS ask what it HOLDS (`hasArea`/`hasAnyArea`), not where it is.

import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/active_area_store.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _admin = Role(id: 1, name: 'admin', displayName: 'Admin');
const _sales = Role(id: 2, name: 'sales', displayName: 'Store Manager');
const _inventory = Role(id: 3, name: 'inventory', displayName: 'Stock Manager');
const _pos = Role(id: 4, name: 'pos', displayName: 'Cashier');

User _account(int id, List<Role> roles) => User(
  id: id,
  username: 'staff$id',
  email: 'staff$id@demo.ph',
  fullName: 'Staff $id',
  role: roles.isEmpty ? null : roles.first,
  roles: roles,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ActiveAreaStore.load();
  });

  AuthViewmodel viewmodelFor(User account) => AuthViewmodel(
    _AreaRepository(account: account),
    areas: const ActiveAreaStore(),
  );

  test('one area signs straight in, with no picker', () async {
    final auth = viewmodelFor(_account(5, [_pos]));

    await auth.login('staff5', 'demo1234');

    expect(auth.assignedAreas, ['pos']);
    expect(auth.activeArea, 'pos');
    expect(auth.roleName, 'pos', reason: 'the guards read roleName');
    expect(auth.needsAreaChoice, isFalse);
    expect(auth.canSwitchArea, isFalse);
  });

  test('several areas need no pick: the union is the account', () async {
    final auth = viewmodelFor(_account(5, [_admin, _pos]));

    await auth.login('staff5', 'demo1234');

    expect(auth.assignedAreas, ['admin', 'pos']);
    expect(
      auth.needsAreaChoice,
      isFalse,
      reason: 'a merged account works from the combined sidebar, no picker',
    );
    expect(auth.activeArea, isNull, reason: 'no single area is active');
    expect(auth.roleName, isNull, reason: 'roleName stays the ACTIVE area');
    expect(auth.canSwitchArea, isTrue);
  });

  test('an action asks which areas the account holds', () async {
    final merged = viewmodelFor(_account(5, [_admin, _pos]));
    await merged.login('staff5', 'demo1234');

    expect(merged.hasArea('pos'), isTrue);
    expect(merged.hasArea('admin'), isTrue);
    expect(merged.hasArea('sales'), isFalse);
    expect(merged.hasAnyArea(const {'inventory', 'sales'}), isFalse);
    expect(merged.hasAnyArea(const {'inventory', 'admin'}), isTrue);

    final cashier = viewmodelFor(_account(6, [_pos]));
    await cashier.login('staff6', 'demo1234');

    expect(cashier.hasArea('pos'), isTrue);
    expect(
      cashier.hasAnyArea(const {'inventory', 'sales', 'admin'}),
      isFalse,
      reason: 'a single Cashier is unchanged: no catalogue action',
    );
  });

  test(
    'a single area has nothing to pick and needs no choice',
    () async {
      final auth = viewmodelFor(_account(5, [_pos]));
      await auth.login('staff5', 'demo1234');

      expect(auth.activeArea, 'pos');
      expect(auth.needsAreaChoice, isFalse);
      expect(auth.canSwitchArea, isFalse);
    },
  );

  test(
    'a merged account ignores the remembered area, single-role keeps it',
    () async {
      final merged = viewmodelFor(_account(5, [_admin, _pos]));
      await merged.login('staff5', 'demo1234');

      // The API still answers in-session, but nothing routes on it.
      await merged.selectArea('pos');
      expect(merged.activeArea, 'pos');

      // F3: the next start of a merged account does NOT restore that pick.
      final again = viewmodelFor(_account(5, [_admin, _pos]));
      await again.initialize();
      expect(
        again.activeArea,
        isNull,
        reason: 'a merged account lands on the combined dashboard every time',
      );

      // A single-area account still gets its remembered area back.
      final single = viewmodelFor(_account(6, [_pos]));
      await single.login('staff6', 'demo1234');
      final singleAgain = viewmodelFor(_account(6, [_pos]));
      await singleAgain.initialize();
      expect(singleAgain.activeArea, 'pos');
    },
  );

  test('a remembered area another account picked is never reused', () async {
    SharedPreferences.setMockInitialValues({ActiveAreaStore.keyFor(1): 'pos'});
    await ActiveAreaStore.load();

    final auth = viewmodelFor(_account(5, [_admin, _sales]));
    await auth.login('staff5', 'demo1234');

    expect(
      auth.activeArea,
      isNull,
      reason: "one user's pick must not place the next user",
    );
    expect(auth.needsAreaChoice, isFalse);
  });

  test('a revoked area does not come back from the preference', () async {
    SharedPreferences.setMockInitialValues({
      ActiveAreaStore.keyFor(5): 'admin',
    });
    await ActiveAreaStore.load();

    final auth = viewmodelFor(_account(5, [_sales, _pos]));
    await auth.login('staff5', 'demo1234');

    expect(auth.assignedAreas, ['sales', 'pos']);
    expect(auth.activeArea, isNull, reason: 'admin was taken away');
    expect(auth.needsAreaChoice, isFalse);
  });

  test('picking an unassigned area is refused, not remembered', () async {
    final auth = viewmodelFor(_account(5, [_pos]));
    await auth.login('staff5', 'demo1234');

    await auth.selectArea('admin');

    expect(auth.activeArea, 'pos');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ActiveAreaStore.keyFor(5)),
      isNull,
      reason: 'a refused pick must not be stored',
    );
  });

  test('switching area is UI state, and only among assigned areas', () async {
    final auth = viewmodelFor(_account(5, [_admin, _sales, _pos]));
    await auth.login('staff5', 'demo1234');
    await auth.selectArea('sales');

    expect(auth.assignedAreas, ['admin', 'sales', 'pos']);
    expect(auth.roleName, 'sales');

    await auth.selectArea('inventory');
    expect(auth.roleName, 'sales', reason: 'inventory was never assigned');
  });

  test('signing out clears the active area and the account', () async {
    final auth = viewmodelFor(_account(5, [_admin, _pos]));
    await auth.login('staff5', 'demo1234');
    await auth.selectArea('pos');

    await auth.logout();

    expect(auth.user, isNull);
    expect(auth.activeArea, isNull);
    expect(auth.assignedAreas, isEmpty);
    expect(auth.needsAreaChoice, isFalse);
    expect(auth.isAuthenticated, isFalse);
  });

  test('an explicit empty roles list leaves no area at all', () async {
    final auth = viewmodelFor(_account(6, const []));

    await auth.login('staff6', 'demo1234');

    expect(auth.assignedAreas, isEmpty);
    expect(auth.activeArea, isNull);
    expect(auth.needsAreaChoice, isFalse, reason: 'there is nothing to pick');
    expect(
      auth.roleName,
      isNull,
      reason: 'unsupported screen, never a dashboard',
    );
  });

  test('a single-role payload with roles absent keeps working', () async {
    // Released server shape: `role` only. The app must not lose the account.
    final auth = AuthViewmodel(
      _AreaRepository(
        account: const User(
          id: 7,
          username: 'old',
          email: 'old@demo.ph',
          fullName: 'Old Client',
          role: _inventory,
        ),
      ),
      areas: const ActiveAreaStore(),
    );

    await auth.login('old', 'demo1234');

    expect(auth.assignedAreas, ['inventory']);
    expect(auth.roleName, 'inventory');
    expect(auth.canSwitchArea, isFalse);
  });

  test('a restored single-area session validates the stored area too', () async {
    SharedPreferences.setMockInitialValues({ActiveAreaStore.keyFor(5): 'pos'});
    await ActiveAreaStore.load();

    final auth = viewmodelFor(_account(5, [_pos]));
    await auth.initialize();

    expect(auth.user?.id, 5);
    expect(auth.activeArea, 'pos');
  });

  test('a stored pick beside a second area is kept, not used', () async {
    SharedPreferences.setMockInitialValues({ActiveAreaStore.keyFor(5): 'pos'});
    await ActiveAreaStore.load();

    final auth = viewmodelFor(_account(5, [_pos, _admin]));
    await auth.initialize();

    expect(auth.activeArea, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(ActiveAreaStore.keyFor(5)),
      'pos',
      reason: 'the store is left alone; a single-area start still uses it',
    );
  });
}

class _AreaRepository extends AuthRepository {
  _AreaRepository({required this.account}) : super(_AreaAuthService());

  final User account;

  @override
  Future<User?> restoreSession() async => account;

  @override
  Future<User> login(String identifier, String password) async => account;

  @override
  Future<void> logout() async {}
}

class _AreaAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async {
    throw const AuthException('not used in these tests');
  }

  @override
  Future<void> logout() async {}
}
