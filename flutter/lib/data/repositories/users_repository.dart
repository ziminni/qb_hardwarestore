import 'package:client/data/models/user.dart';
import 'package:client/data/services/user_service.dart';

/// Policy-free pass-through over [UserService], preserving the one data path
/// View -> ViewModel -> Repository -> Service -> ApiClient.
class UsersRepository {
  UsersRepository({UserService? service}) : _service = service ?? UserService();

  final UserService _service;

  Future<List<User>> fetchUsers({String? search}) =>
      _service.fetchUsers(search: search);

  Future<UserStats> fetchUserStats() => _service.fetchUserStats();

  Future<User> createUser({
    required String username,
    required String email,
    required String fullName,
    required String password,
    required String groupName,
  }) => _service.createUser(
    username: username,
    email: email,
    fullName: fullName,
    password: password,
    groupName: groupName,
  );
}
