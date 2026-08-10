
class AuthService {
  Future<Map <String, dynamic>?> login (
    String email,
    String password,
  ) async {
    if (email == "admin@test.com" && password == "password") {
      return {
        "id" : 001,
        "email" : "admin@test.com"
      };
    }

    return null;
  }
}