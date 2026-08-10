import '../models/user.dart';
import 'package:client/data/services/auth_service.dart';

class AuthRepository {
  final AuthService authService;

  AuthRepository(
    this.authService
  );

  Future<User?> login(String email, String password) async {
    final data = await authService.login(email, password);

    if (data == null) {
      return null;
    }

    return User(
      id: data["id"],
      email: data["email"],
    );
  }
}
