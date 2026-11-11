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

  /// Role codes the role picker may offer, code -> label.
  ///
  /// The wire takes CODES (`roles: ['pos', 'sales']`), so this map is keyed by
  /// code and the label is only what the chip shows. Managers get the working
  /// areas; `admin` stays an admin-only offer (the server refuses it to anyone
  /// else with 403 `USER_ADMIN_FORBIDDEN` anyway, and a manager must not be able
  /// to grant, remove or edit through a mixed list either).
  /// `Site Foreman` is deliberately ABSENT (decision 01): it was a CPMS
  /// identity with no POS screen, and the group no longer exists server-side.
  static Map<String, String> assignableRoles({required bool isAdmin}) => {
    'pos': 'Cashier',
    'inventory': 'Stock Manager',
    'sales': 'Store Manager',
    if (isAdmin) 'admin': 'Admin',
  };

  /// The code that may not be handed to a manager, so the guard reads one home.
  static const String adminRoleCode = 'admin';

  /// True when [codes] would change admin authority.
  static bool touchesAdmin(Iterable<String> codes) =>
      codes.contains(adminRoleCode);

  List<User> get users => List.unmodifiable(
    _rows.where((user) {
      if (_roleFilter != null && !user.roleLabels.contains(_roleFilter)) {
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

  /// Every role label present in the loaded rows, one entry per role.
  ///
  /// No invented roles: the control can only offer what the server sent —
  /// which includes [User.noRoleLabel], because a groupless account is a real
  /// row and filtering to it is how an admin finds one to fix. An account with
  /// several roles therefore appears under each of them.
  List<String> get availableRoles =>
      {for (final user in _rows) ...user.roleLabels}.toList()..sort();
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

  /// Replaces [user]'s roles, then reloads so the row comes from the server.
  ///
  /// `roles[]` is a FULL replacement: a code left out is a code removed, so the
  /// dialog always sends the whole list. A manager may not send `admin` (not
  /// even beside other codes), and an admin refusal keeps the rows and names
  /// itself in [actionError] — the server sentence for `LAST_ADMIN` and
  /// `USER_ADMIN_FORBIDDEN` included.
  Future<bool> assignRoles(
    User user, {
    required List<String> roleCodes,
    required bool isAdminViewer,
  }) async {
    _actionError = null;
    if (roleCodes.isEmpty) {
      _actionError = 'Choose at least one role.';
      notifyListeners();
      return false;
    }
    if (!isAdminViewer && touchesAdmin(roleCodes)) {
      _actionError = 'Only an Admin may grant Admin authority.';
      notifyListeners();
      return false;
    }
    notifyListeners();
    try {
      await _users.assignRoles(id: user.id, roles: roleCodes);
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
  /// the register endpoint demands a password of at least 8 characters and at
  /// least one role, and a round trip to learn that would be waste. The payload
  /// carries `roles[]` only: sending a legacy `group_name` beside it is refused
  /// with 400 `ROLES_CONFLICT`.
  Future<bool> create({
    required String username,
    required String email,
    required String fullName,
    required String password,
    required List<String> roleCodes,
    required bool isAdminViewer,
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
    if (roleCodes.isEmpty) {
      _createError = 'Choose at least one role.';
      notifyListeners();
      return false;
    }
    if (!isAdminViewer && touchesAdmin(roleCodes)) {
      _createError = 'Only an Admin may grant Admin authority.';
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
        roles: roleCodes,
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
