import 'package:client/data/models/user.dart';
import 'package:client/data/services/user_service.dart';
import 'package:flutter/foundation.dart';

/// Owns the admin User Management screen.
///
/// Lists staff accounts with the server-computed totals, searches
/// server-side, and creates accounts through the register shape (which
/// mandates a group). A created row reloads the list because the server owns
/// ids and role resolution.
class AdminUsersViewmodel extends ChangeNotifier {
  AdminUsersViewmodel({UserService? users}) : _users = users ?? UserService();

  final UserService _users;

  List<User> _rows = const [];
  UserStats? _stats;
  bool _isLoading = false;
  String? _loadError;
  String? _createError;
  String? _actionError;

  String _query = '';
  String? _roleFilter;
  bool? _activeFilter;

  /// Rows after the client-side role/status filters. Search itself runs
  /// server-side (`?search=`), so this only narrows what is already loaded.
  /// The last account-creation refusal. Kept apart from [_loadError] so a
  /// cancelled dialog never leaves a stale banner under a loaded table.
  String? get createError => _createError;

  /// The last deactivate/reactivate/role-change refusal. Kept apart from
  /// [_loadError] and [_createError] so a cancelled action dialog never
  /// leaves a stale banner under a loaded table.
  String? get actionError => _actionError;

  /// Groups the role picker may offer. Managers get the working groups;
  /// the Admin groups stay an admin-only offer (the server refuses them to
  /// anyone else with 403 `USER_ADMIN_FORBIDDEN` anyway).
  ///
  /// Compare by GROUP name (what `assign_role` takes), never by display
  /// label or client role code — the Phase 4 Resolve outage was a test that
  /// used a label where the wire carries a code.
  static List<String> assignableGroups({required bool isAdmin}) => [
    'Cashier',
    'Stock Manager',
    'Store Manager',
    'Site Foreman',
    if (isAdmin) ...['Admin', 'System Administrator'],
  ];

  List<User> get users => List.unmodifiable(
    _rows.where((user) {
      if (_roleFilter != null && user.roleLabel != _roleFilter) {
        return false;
      }
      if (_activeFilter != null && user.isActive != _activeFilter) {
        return false;
      }
      return true;
    }),
  );

  String get searchQuery => _query;
  String? get roleFilter => _roleFilter;
  bool? get activeFilter => _activeFilter;

  /// Distinct role names present in the loaded rows, for the filter control.
  /// No invented roles: the control can only offer what the server sent —
  /// which includes [User.noRoleLabel], because a groupless account is a real
  /// row and filtering to it is how an admin finds one to fix.
  List<String> get availableRoles =>
      {for (final user in _rows) user.roleLabel}.toList()..sort();
  UserStats? get stats => _stats;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  bool get hasLoaded => _stats != null;

  /// Loads the account list (optionally filtered) plus the totals.
  ///
  /// A failed load keeps the rows already shown: an empty table would read as
  /// "no staff accounts", which is a different and far more dangerous
  /// statement than "this did not load".
  Future<void> load({String? search}) async {
    if (search != null) _query = search;
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _users.fetchUsers(search: _query.isEmpty ? null : _query),
        _users.fetchUserStats(),
      ]);
      _rows = (results[0] as List<User>).toList();
      _stats = results[1] as UserStats;
      _loadError = null;
    } on UsersServiceException catch (error) {
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Narrows the loaded rows client-side. Null clears that dimension.
  void setRoleFilter(String? role) {
    _roleFilter = role;
    notifyListeners();
  }

  /// Narrows the loaded rows client-side. Null clears that dimension.
  void setActiveFilter(bool? active) {
    _activeFilter = active;
    notifyListeners();
  }

  /// Clears every filter and reloads the full list from the server.
  Future<void> clearFilters() async {
    _query = '';
    _roleFilter = null;
    _activeFilter = null;
    await load();
  }

  /// Flips `is_active` for [user], then reloads so the row comes from the
  /// server (the owner of ids, roles and the LAST_ADMIN guard).
  ///
  /// A refused write keeps the rows already shown and names the failure in
  /// [actionError]: an empty table would read as "no staff accounts".
  Future<bool> setActive(User user, {required bool isActive}) async {
    _actionError = null;
    notifyListeners();
    try {
      await _users.setActive(id: user.id, isActive: isActive);
      await load();
      return _loadError == null;
    } on UsersServiceException catch (error) {
      _actionError = error.message;
      notifyListeners();
      return false;
    }
  }

  /// Replaces [user]'s group, then reloads so the row comes from the server.
  ///
  /// Membership is replaced, so assigning a non-admin group demotes. Like
  /// [setActive], a refusal keeps the rows and names itself in [actionError].
  Future<bool> assignRole(User user, {required String groupName}) async {
    _actionError = null;
    notifyListeners();
    try {
      await _users.assignRole(id: user.id, groupName: groupName);
      await load();
      return _loadError == null;
    } on UsersServiceException catch (error) {
      _actionError = error.message;
      notifyListeners();
      return false;
    }
  }

  /// Clears a stale action refusal, e.g. when its dialog is dismissed.
  void clearActionError() {
    _actionError = null;
    notifyListeners();
  }

  /// Creates an account, then reloads so the new row comes from the server.
  ///
  /// Returns false without touching the server when the input is invalid:
  /// the register endpoint demands a password of at least 8 characters and
  /// a group, and a round trip to learn that would be waste.
  Future<bool> create({
    required String username,
    required String email,
    required String fullName,
    required String password,
    required String groupName,
  }) async {
    if (username.trim().isEmpty ||
        email.trim().isEmpty ||
        fullName.trim().isEmpty) {
      _createError = 'Name, username and email are required.';
      notifyListeners();
      return false;
    }
    if (password.length < 8) {
      _createError = 'The password must be at least 8 characters.';
      notifyListeners();
      return false;
    }
    _createError = null;
    try {
      await _users.createUser(
        username: username.trim(),
        email: email.trim(),
        fullName: fullName.trim(),
        password: password,
        groupName: groupName,
      );
      await load();
      return _loadError == null;
    } on UsersServiceException catch (error) {
      _createError = error.message;
      notifyListeners();
      return false;
    }
  }
}
