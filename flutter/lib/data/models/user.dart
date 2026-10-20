import 'role.dart';

class User {
  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.role,
    this.isActive = true,
  });

  final int id;
  final String username;
  final String email;
  final String fullName;
  final Role role;
  final bool isActive;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      role: _roleFromJson(json['role']),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

Role _roleFromJson(Object? raw) {
  // The register endpoint mandates a group precisely because a groupless
  // account carries a null role that the old `as Map` cast turned into a
  // TypeError far from the wire. Fail here, loudly, at the boundary.
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
