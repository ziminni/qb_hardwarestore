import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/services/user_service.dart';
import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubUsersService extends UserService {
  _StubUsersService() : super();

  List<User> users = const [];
  String? failure;
  int createCalls = 0;
  String? lastSearch;

  @override
  Future<List<User>> fetchUsers({String? search}) async {
    lastSearch = search;
    final failure = this.failure;
    if (failure != null) throw UsersServiceException(failure);
    return users;
  }

  @override
  Future<UserStats> fetchUserStats() async =>
      const UserStats(total: 5, active: 4, inactive: 1, rolesAssigned: 3);

  @override
  Future<User> createUser({
    required String username,
    required String email,
    required String fullName,
    required String password,
    required String groupName,
  }) async {
    createCalls++;
    return const User(
      id: 9,
      username: 'newcashier',
      email: 'new@demo.ph',
      fullName: 'New Cashier',
      role: Role(id: 3, name: 'pos', displayName: 'Cashier'),
    );
  }
}

void main() {
  late _StubUsersService service;
  late AdminUsersViewmodel viewmodel;

  setUp(() {
    service = _StubUsersService();
    viewmodel = AdminUsersViewmodel(users: service);
  });

  test('users and stats load together', () async {
    service.users = const [
      User(
        id: 2,
        username: 'manager',
        email: 'm@demo.ph',
        fullName: 'Mana Ger',
        role: Role(id: 3, name: 'sales', displayName: 'Store Manager'),
      ),
    ];

    await viewmodel.load();

    expect(viewmodel.users.single.username, 'manager');
    expect(viewmodel.stats?.total, 5);
    expect(viewmodel.loadError, isNull);
  });

  test('a failed load keeps the rows it already had', () async {
    service.users = const [
      User(
        id: 2,
        username: 'manager',
        email: 'm@demo.ph',
        fullName: 'Mana Ger',
        role: Role(id: 3, name: 'sales', displayName: 'Store Manager'),
      ),
    ];
    await viewmodel.load();
    service.users = const [];
    service.failure = 'Cannot connect to the BuildPro server.';

    await viewmodel.load();

    expect(viewmodel.loadError, contains('Cannot connect'));
    expect(viewmodel.users, hasLength(1));
  });

  test('search passes the query to the server', () async {
    service.users = const [];

    await viewmodel.load(search: 'mana');

    expect(service.lastSearch, 'mana');
  });

  test('role and status narrow the loaded rows client-side', () async {
    service.users = const [
      User(
        id: 2,
        username: 'manager',
        email: 'm@demo.ph',
        fullName: 'Mana Ger',
        role: Role(id: 3, name: 'sales', displayName: 'Store Manager'),
      ),
      User(
        id: 3,
        username: 'cashier',
        email: 'c@demo.ph',
        fullName: 'Cashy Ir',
        role: Role(id: 4, name: 'pos', displayName: 'Cashier'),
        isActive: false,
      ),
    ];
    await viewmodel.load();

    viewmodel.setRoleFilter('Cashier');
    expect(viewmodel.users.map((u) => u.username), ['cashier']);

    viewmodel.setRoleFilter(null);
    viewmodel.setActiveFilter(true);
    expect(viewmodel.users.map((u) => u.username), ['manager']);
  });

  test('clearFilters resets everything and reloads', () async {
    service.users = const [
      User(
        id: 2,
        username: 'manager',
        email: 'm@demo.ph',
        fullName: 'Mana Ger',
        role: Role(id: 3, name: 'sales', displayName: 'Store Manager'),
      ),
    ];
    await viewmodel.load(search: 'mana');
    viewmodel.setRoleFilter('Cashier');

    await viewmodel.clearFilters();

    expect(viewmodel.searchQuery, isEmpty);
    expect(viewmodel.roleFilter, isNull);
    expect(service.lastSearch, isNull);
    expect(viewmodel.users, hasLength(1));
  });

  test('create refuses a short password without touching the server', () async {
    final ok = await viewmodel.create(
      username: 'x',
      email: 'x@demo.ph',
      fullName: 'X',
      password: 'short',
      groupName: 'Cashier',
    );

    expect(ok, isFalse);
    expect(service.createCalls, 0);
    expect(viewmodel.createError, contains('8 characters'));
    // A refused create never touches the page banner.
    expect(viewmodel.loadError, isNull);
  });
}
