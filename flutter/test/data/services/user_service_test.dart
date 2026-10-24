import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/services/user_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  ResponseBody Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

Map<String, dynamic> _user({int id = 2, String username = 'manager'}) => {
  'id': id,
  'username': username,
  'email': '$username@demo.ph',
  'full_name': 'Mana Ger',
  'is_active': true,
  'is_staff': false,
  'role': {
    'id': 3,
    'name': 'sales',
    'display_name': 'Store Manager',
    'permissions': [],
  },
  'role_names': ['Store Manager'],
  'last_login': null,
  'created_at': '2026-10-19T08:00:00Z',
  'updated_at': '2026-10-19T08:00:00Z',
};

void main() {
  late _FakeAdapter adapter;
  late UserService service;
  RequestOptions? lastRequest;

  setUpAll(() {
    ApiClient.instance.init();
  });

  setUp(() {
    lastRequest = null;
    adapter = _FakeAdapter((options) {
      lastRequest = options;
      return _json({'count': 0, 'next': null, 'previous': null, 'results': []});
    });
    ApiClient.instance.dio.httpClientAdapter = adapter;
    service = UserService();
  });

  test('users parse with roles joined from the wire', () async {
    adapter.respond = (options) {
      lastRequest = options;
      return _json({
        'count': 1,
        'next': null,
        'previous': null,
        'results': [_user()],
      });
    };

    final users = await service.fetchUsers();

    expect(users.single.username, 'manager');
    expect(users.single.roleLabel, 'Store Manager');
    expect(users.single.isActive, isTrue);
  });

  test('search passes through as a query parameter', () async {
    await service.fetchUsers(search: 'mana');

    expect(lastRequest?.queryParameters['search'], 'mana');
  });

  test('a role-less row parses as a null role, not a failure', () {
    // `GET /users/` really returns `role: null` for a groupless account (a
    // superuser, an account whose group was removed). Phase 3 Task 0: that row
    // parses; it must not fail the whole staff list.
    final row = _user()..['role'] = null;

    final user = User.fromJson(row);

    expect(user.role, isNull);
    expect(user.roleLabel, User.noRoleLabel);
  });

  test('stats parse totals', () async {
    adapter.respond = (_) =>
        _json({'total': 5, 'active': 4, 'inactive': 1, 'roles_assigned': 3});

    final stats = await service.fetchUserStats();

    expect(stats.total, 5);
    expect(stats.inactive, 1);
    expect(stats.rolesAssigned, 3);
  });

  test('create posts the register shape and returns the row', () async {
    Map<String, dynamic>? sent;
    adapter.respond = (options) {
      lastRequest = options;
      sent = options.data as Map<String, dynamic>?;
      return _json(_user(id: 9, username: 'newcashier'), status: 201);
    };

    final created = await service.createUser(
      username: 'newcashier',
      email: 'new@demo.ph',
      fullName: 'New Cashier',
      password: 'demo1234',
      groupName: 'Cashier',
    );

    expect(sent?['group_name'], 'Cashier');
    expect(sent?['password'], 'demo1234');
    expect(created.id, 9);
  });

  test('a groupless row does not fail the staff list', () async {
    adapter.respond = (_) => _json({
      'count': 2,
      'results': [
        _user(),
        {
          'id': 7,
          'username': 'ghost',
          'email': 'g@demo.ph',
          'full_name': 'Ghost Account',
          'is_active': true,
          'role': null,
        },
      ],
    });

    final users = await service.fetchUsers();

    expect(users, hasLength(2));
    expect(users.first.roleLabel, 'Store Manager');
    expect(users.last.role, isNull);
    expect(users.last.fullName, 'Ghost Account');
  });

  test('a row with a non-object role is still a load error', () async {
    // A string where an object belongs is a contract break — not the
    // groupless case. It keeps failing as a load error with a retry.
    adapter.respond = (_) => _json({
      'count': 1,
      'results': [
        {
          'id': 7,
          'username': 'ghost',
          'email': 'g@demo.ph',
          'full_name': 'Ghost Account',
          'role': 'Store Manager',
        },
      ],
    });

    await expectLater(
      service.fetchUsers(),
      throwsA(isA<UsersServiceException>()),
    );
  });

  test('a 403 refusal reads as a permission error, not a load error', () async {
    adapter.respond = (_) => _json({
      'detail': 'You do not have permission to perform this action.',
    }, status: 403);

    expect(
      service.fetchUsers(),
      throwsA(
        isA<UsersServiceException>().having(
          (e) => (e).message,
          'message',
          contains('permission'),
        ),
      ),
    );
  });
}
