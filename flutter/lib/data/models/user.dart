import 'role.dart';

class User {
  /// What an account with no group is called on screen. `GET /users/` really
  /// does return `role: null` for one (a superuser, or an account whose group
  /// was removed), and a blank ROLE cell reads as a rendering bug.
  static const String noRoleLabel = 'No role';

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.role,
    this.roles,
    this.isActive = true,
  });

  final int id;
  final String username;
  final String email;
  final String fullName;

  /// The original single role object. Kept for released clients and for the
  /// server's own "first group" answer; it is NOT the list of areas.
  final Role? role;

  /// `roles[]` from the wire: every area the account holds, in the server's
  /// stable order (admin, sales, inventory, pos).
  ///
  /// Null means the field was ABSENT from the payload (an older server or a
  /// hand-built `User`): the account then keeps the single-role behaviour of
  /// [role]. An explicit empty list is a different fact — it is what a CPMS
  /// service or roleless account sends, and it must never be turned into
  /// access.
  final List<Role>? roles;
  final bool isActive;

  /// Every area the account holds, with the legacy single-role fallback.
  List<Role> get assignedRoles =>
      roles ?? (role == null ? const <Role>[] : <Role>[role!]);

  /// The area codes in server order, lower-cased for comparison.
  List<String> get areaCodes => [for (final role in assignedRoles) role.code];

  /// One label per assigned role, or the single legacy label.
  List<String> get roleLabels => assignedRoles.isEmpty
      ? [role?.displayName ?? noRoleLabel]
      : [for (final role in assignedRoles) role.displayName];

  /// The label to show for this account's roles, or [noRoleLabel].
  String get roleLabel => roleLabels.join(', ');

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      role: _roleFromJson(json['role']),
      roles: _rolesFromJson(json['roles']),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// `roles[]`, or null when the field is absent.
///
/// Absent and empty are different facts (single-role compatibility vs an
/// account with no area at all), so the absence is preserved instead of being
/// flattened into an empty list. Anything present that is not a list of
/// objects is a contract break, like a non-object `role`.
List<Role>? _rolesFromJson(Object? raw) {
  if (raw == null) return null;
  if (raw is! List) {
    throw const FormatException('Field "roles" must be a list');
  }
  return [
    for (final entry in raw)
      if (entry is Map<String, dynamic>)
        Role.fromJson(entry)
      else
        throw const FormatException('Field "roles" must hold role objects'),
  ];
}

Role? _roleFromJson(Object? raw) {
  // A groupless account is a REAL state, not a contract break: `GET /users/`
  // returns `role: null` for a Django superuser or an account whose group was
  // removed (Phase 3 Task 0). Throwing here failed the entire staff list —
  // one row took the whole screen down with it.
  //
  // Anything present that is not an object is still a break and still throws
  // at the boundary, far from the wire, rather than being flattened into "no
  // role".
  if (raw == null) return null;
  if (raw is! Map<String, dynamic>) {
    throw FormatException('Missing required object field "role"');
  }
  return Role.fromJson(raw);
}

/// Account totals behind the admin User Management metric cards.
class UserStats {
  const UserStats({
    required this.total,
    required this.active,
    required this.inactive,
    required this.rolesAssigned,
  });

  final int total;
  final int active;
  final int inactive;
  final int rolesAssigned;

  factory UserStats.fromJson(Map<String, dynamic> json) => UserStats(
    total: json['total'] as int,
    active: json['active'] as int,
    inactive: json['inactive'] as int,
    rolesAssigned: json['roles_assigned'] as int,
  );
}

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final User user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['access'] as String,
      refreshToken: json['refresh'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}
