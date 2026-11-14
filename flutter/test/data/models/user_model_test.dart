// Phase 3 Task 0 (U): `GET /users/` legitimately returns `role: null` for an
// account with no group — Django `createsuperuser`, an account created in the
// Django admin, or one whose group was removed. `User.fromJson` used to throw
// `FormatException('Missing required object field "role"')` on that row, which
// failed the WHOLE staff list.
//
// The rule after the fix: a missing role is a real state and parses to null.
// Every OTHER required field still fails loudly — silently substituting nulls
// for id/username/email/full_name would move the failure far from the wire.

import 'package:client/data/models/user.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row({Object? role = _sentinel}) => {
  'id': 7,
  'username': 'ghost',
  'email': 'g@demo.ph',
  'full_name': 'Ghost Account',
  'is_active': true,
  if (!identical(role, _sentinel)) 'role': role,
};

/// Distinguishes "role key absent" from "role: null" in the fixtures.
const _sentinel = Object();

void main() {
  test('a null role parses to a null role, not an exception', () {
    final user = User.fromJson(_row(role: null));

    expect(user.role, isNull);
    expect(user.username, 'ghost');
    expect(user.fullName, 'Ghost Account');
  });

  test('a missing role key parses to a null role too', () {
    expect(User.fromJson(_row()).role, isNull);
  });

  test(
    'the role-less account reads as "No role" wherever a label is needed',
    () {
      expect(User.fromJson(_row(role: null)).roleLabel, User.noRoleLabel);
      expect(
        User.fromJson(
          _row(
            role: {
              'id': 3,
              'name': 'sales',
              'display_name': 'Store Manager',
              'permissions': <int>[],
            },
          ),
        ).roleLabel,
        'Store Manager',
      );
    },
  );

  test('a role that is not an object still fails loudly', () {
    // A string where an object belongs is a contract break, not a groupless
    // account. It must not be swallowed into "No role".
    expect(
      () => User.fromJson(_row(role: 'Store Manager')),
      throwsA(isA<FormatException>()),
    );
  });

  test('other required fields still fail loudly', () {
    final missingId = _row(role: null)..remove('id');
    expect(() => User.fromJson(missingId), throwsA(isA<TypeError>()));

    final missingName = _row(role: null)..remove('full_name');
    expect(() => User.fromJson(missingName), throwsA(isA<TypeError>()));
  });
}
