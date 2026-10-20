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

  String _query = '';
  String? _roleFilter;
  bool? _activeFilter;

  /// Rows after the client-side role/status filters. Search itself runs
  /// server-side (`?search=`), so this only narrows what is already loaded.
  List<User> get users => List.unmodifiable(
    _rows.where((user) {
      if (_roleFilter != null && user.role.displayName != _roleFilter) {
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
  /// No invented roles: the control can only offer what the server sent.
  List<String> get availableRoles => {
    for (final user in _rows) user.role.displayName,
  }.toList()..sort();
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
      _loadError = 'Name, username and email are required.';
      notifyListeners();
      return false;
    }
    if (password.length < 8) {
      _loadError = 'The password must be at least 8 characters.';
      notifyListeners();
      return false;
    }
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
      _loadError = error.message;
      notifyListeners();
      return false;
    }
  }
}
