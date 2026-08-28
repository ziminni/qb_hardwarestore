import 'role.dart';

class User {
  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    required this.role,
  });

  final int id;
  final String username;
  final String email;
  final String fullName;
  final Role role;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      role: Role.fromJson(json['role'] as Map<String, dynamic>),
    );
  }
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
