// Phase 4 F3b: `roles[]` beside the original `role` object.
//
// Three wire states must stay apart, because each means a different amount of
// access:
//   - `roles` ABSENT        -> an old server or a hand-built User: single role.
//   - `roles` present, []   -> a CPMS service or role-less account: no area.
//   - `roles` present, [..] -> every area the account holds, server order.
//
// Collapsing any two of them is how a stale preference or an empty list turns
// into access the server never granted.

import 'package:client/data/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _roleJson(int id, String name, String displayName) => {
  'id': id,
  'name': name,
  'display_name': displayName,
  'permissions': <int>[],
};

Map<String, dynamic> _wire({
  Object? role = const _Absent(),
  Object? roles = const _Absent(),
}) => {
  'id': 7,
  'username': 'ana',
  'email': 'ana@demo.ph',
  'full_name': 'Ana Cruz',
  'is_active': true,
  if (role is! _Absent) 'role': role,
  if (roles is! _Absent) 'roles': roles,
};

class _Absent {
  const _Absent();
}

void main() {
  test('roles[] parses every assigned area in server order', () {
    final user = User.fromJson(
      _wire(
        role: _roleJson(3, 'admin', 'Admin'),
        roles: [
          _roleJson(3, 'admin', 'Admin'),
          _roleJson(12, 'pos', 'Cashier'),
        ],
      ),
    );

    expect(user.areaCodes, ['admin', 'pos']);
    expect(
      user.role?.displayName,
      'Admin',
      reason: 'the original role object is kept as it arrived',
    );
  });

  test('a payload without roles keeps the single legacy role', () {
    final user = User.fromJson(
      _wire(role: _roleJson(2, 'sales', 'Store Manager')),
    );

    expect(user.roles, isNull, reason: 'absent stays absent');
    expect(user.areaCodes, ['sales']);
    expect(user.roleLabel, 'Store Manager');
  });

  test('explicit empty roles grants no area, and never invents one', () {
    // The CPMS shape: `role` still names a group, `roles[]` is empty because a
    // CPMS service account has no POS area.
    final user = User.fromJson(
      _wire(
        role: _roleJson(9, 'cpms', 'CPMS Service'),
        roles: const <Object>[],
      ),
    );

    expect(user.roles, isEmpty);
    expect(user.areaCodes, isEmpty);
    expect(
      user.roleLabel,
      'CPMS Service',
      reason: 'the row still has to name the account it is',
    );
  });

  test('a role-less account has no area and reads No role', () {
    final user = User.fromJson(_wire(role: null, roles: const <Object>[]));

    expect(user.areaCodes, isEmpty);
    expect(user.roleLabel, User.noRoleLabel);
  });

  test('the role summary names every role', () {
    final user = User.fromJson(
      _wire(
        roles: [
          _roleJson(3, 'admin', 'Admin'),
          _roleJson(12, 'pos', 'Cashier'),
        ],
      ),
    );

    expect(user.roleLabel, 'Admin, Cashier');
    expect(user.roleLabels, ['Admin', 'Cashier']);
  });

  test('a non-list roles field is a contract break', () {
    expect(
      () => User.fromJson(_wire(role: null, roles: 'pos')),
      throwsA(isA<FormatException>()),
    );
  });

  test('a roles list holding a non-object is a contract break', () {
    expect(
      () => User.fromJson(_wire(role: null, roles: const ['pos'])),
      throwsA(isA<FormatException>()),
    );
  });
}
