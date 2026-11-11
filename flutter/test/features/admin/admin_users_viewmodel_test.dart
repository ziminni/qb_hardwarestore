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
  List<String>? lastCreateRoles;

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
    required List<String> roles,
  }) async {
    createCalls++;
    lastCreateRoles = roles;
    return const User(
      id: 9,
      username: 'newcashier',
      email: 'new@demo.ph',
      fullName: 'New Cashier',
      role: Role(id: 3, name: 'pos', displayName: 'Cashier'),
    );
  }

  int setActiveCalls = 0;
  int? lastActiveId;
  bool? lastActiveValue;
  int assignCalls = 0;
  int? lastAssignId;
  List<String>? lastAssignRoles;

  @override
  Future<User> setActive({required int id, required bool isActive}) async {
    setActiveCalls++;
    lastActiveId = id;
    lastActiveValue = isActive;
    final failure = this.failure;
    if (failure != null) throw UsersServiceException(failure);
    // Simulates the server: the flip is visible only on the next fetch, so a
    // viewmodel that skips its reload keeps showing the stale row.
    users = [
      for (final u in users)
        if (u.id == id)
          User(
            id: u.id,
            username: u.username,
            email: u.email,
            fullName: u.fullName,
            role: u.role,
            isActive: isActive,
          )
        else
          u,
    ];
    return users.firstWhere((u) => u.id == id);
  }

  @override
  Future<User> assignRoles({
    required int id,
    required List<String> roles,
  }) async {
    assignCalls++;
    lastAssignId = id;
    lastAssignRoles = roles;
    final failure = this.failure;
    if (failure != null) throw UsersServiceException(failure);
    return const User(
      id: 2,
      username: 'manager',
      email: 'm@demo.ph',
      fullName: 'Mana Ger',
      role: Role(id: 4, name: 'pos', displayName: 'Cashier'),
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

  // Phase 5 Task 2: deactivate/reactivate + role change reload from the
  // server; a refused write names the failure and keeps the rows.
  test('deactivate flips the row and reloads from the server', () async {
    service.users = const [
      User(
        id: 2,
        username: 'cashier',
        email: 'c@demo.ph',
        fullName: 'Cashy Ir',
        role: Role(id: 4, name: 'pos', displayName: 'Cashier'),
      ),
    ];
    await viewmodel.load();
    final calls = service.setActiveCalls;

    final ok = await viewmodel.setActive(
      viewmodel.users.single,
      isActive: false,
    );

    expect(ok, isTrue);
    expect(service.setActiveCalls, calls + 1);
    expect(service.lastActiveId, 2);
    expect(service.lastActiveValue, isFalse);
    expect(viewmodel.actionError, isNull);
    // The stub flips server-side on write: only a reload shows it.
    expect(viewmodel.users.single.isActive, isFalse);
  });

  test('a refused write names the failure and keeps the rows', () async {
    service.users = const [
      User(
        id: 1,
        username: 'admin',
        email: 'a@demo.ph',
        fullName: 'Ada Ministrator',
        role: Role(id: 1, name: 'admin', displayName: 'Admin'),
      ),
    ];
    await viewmodel.load();
    service.failure = 'This change would leave no active admin.';

    final ok = await viewmodel.setActive(
      viewmodel.users.single,
      isActive: false,
    );

    expect(ok, isFalse);
    expect(viewmodel.actionError, contains('no active admin'));
    expect(viewmodel.users, hasLength(1));
    expect(viewmodel.loadError, isNull);
  });

  test('assignRoles posts the whole code list and reloads the row', () async {
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

    final ok = await viewmodel.assignRoles(
      viewmodel.users.single,
      roleCodes: const ['pos', 'sales'],
      isAdminViewer: true,
    );

    expect(ok, isTrue);
    expect(service.assignCalls, 1);
    expect(service.lastAssignId, 2);
    expect(service.lastAssignRoles, [
      'pos',
      'sales',
    ], reason: 'roles[] is a full replacement, so every code travels');
    expect(viewmodel.actionError, isNull);
  });

  test('a manager cannot grant admin through a mixed list', () async {
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

    final ok = await viewmodel.assignRoles(
      viewmodel.users.single,
      roleCodes: const ['pos', 'admin'],
      isAdminViewer: false,
    );

    expect(ok, isFalse);
    expect(service.assignCalls, 0, reason: 'refused before the wire');
    expect(viewmodel.actionError, contains('Admin'));
  });

  test('an empty role list is refused without a request', () async {
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

    final ok = await viewmodel.assignRoles(
      viewmodel.users.single,
      roleCodes: const [],
      isAdminViewer: true,
    );

    expect(ok, isFalse);
    expect(service.assignCalls, 0);
    expect(viewmodel.actionError, contains('at least one role'));
  });

  test('managers are offered the working roles only; admins also admin', () {
    expect(
      AdminUsersViewmodel.assignableRoles(isAdmin: false).keys,
      containsAll(['pos', 'inventory', 'sales']),
    );
    expect(
      AdminUsersViewmodel.assignableRoles(isAdmin: false).keys,
      isNot(contains('admin')),
    );
    expect(
      AdminUsersViewmodel.assignableRoles(isAdmin: true).keys,
      containsAll(['admin', 'pos', 'inventory', 'sales']),
    );
    // The chip words are the server's, the keys are the codes on the wire.
    expect(
      AdminUsersViewmodel.assignableRoles(isAdmin: true)['pos'],
      'Cashier',
    );
  });

  // Decision 01: the Site Foreman group no longer exists (it was a CPMS
  // identity), so an admin must not be able to hand it out.
  test('Site Foreman is not assignable', () {
    for (final isAdmin in const [false, true]) {
      expect(
        AdminUsersViewmodel.assignableRoles(isAdmin: isAdmin).values,
        isNot(contains('Site Foreman')),
        reason: 'isAdmin: $isAdmin',
      );
    }
  });

  test('create refuses a short password without touching the server', () async {
    final ok = await viewmodel.create(
      username: 'x',
      email: 'x@demo.ph',
      fullName: 'X',
      password: 'short',
      roleCodes: const ['pos'],
      isAdminViewer: true,
    );

    expect(ok, isFalse);
    expect(service.createCalls, 0);
    expect(viewmodel.createError, contains('8 characters'));
    // A refused create never touches the page banner.
    expect(viewmodel.loadError, isNull);
  });

  test('create sends roles[] only, the full list the person picked', () async {
    final ok = await viewmodel.create(
      username: 'newcashier',
      email: 'new@demo.ph',
      fullName: 'New Cashier',
      password: 'demo1234',
      roleCodes: const ['pos', 'sales'],
      isAdminViewer: true,
    );

    expect(ok, isTrue);
    expect(service.createCalls, 1);
    expect(service.lastCreateRoles, ['pos', 'sales']);
  });

  test('a manager cannot create an admin account', () async {
    final ok = await viewmodel.create(
      username: 'newadmin',
      email: 'new@demo.ph',
      fullName: 'New Admin',
      password: 'demo1234',
      roleCodes: const ['admin', 'pos'],
      isAdminViewer: false,
    );

    expect(ok, isFalse);
    expect(service.createCalls, 0);
    expect(viewmodel.createError, contains('Admin'));
  });
}
