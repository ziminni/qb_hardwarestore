import 'package:client/core/constants/app_areas.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/active_area_store.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:flutter/foundation.dart';

class AuthViewmodel extends ChangeNotifier {
  AuthViewmodel(
    this.repository, {
    ActiveAreaStore areas = const ActiveAreaStore(),
  }) : _areas = areas;

  final AuthRepository repository;

  /// The remembered area, per account on this device. A convenience only: every
  /// restored pick is re-validated against the assignment below.
  final ActiveAreaStore _areas;

  bool isInitializing = true;
  bool isLoading = false;
  User? user;
  String? error;

  /// The area this person is working in right now, if they have chosen one.
  String? _activeArea;

  bool get isAuthenticated => user != null;

  /// The areas the server assigned this account, in its own order.
  ///
  /// Read from `roles[]` (every area, widest first); an account whose payload
  /// carries no `roles` keeps its single legacy `role`. Unknown codes are
  /// dropped here so no later check has to wonder about them.
  List<String> get assignedAreas => [
    for (final role in user?.assignedRoles ?? const <Role>[])
      if (AppAreas.contains(role.code)) role.code,
  ];

  /// The assigned areas with their server labels, for the picker and the
  /// header switcher. One list, so both offer the same choices in the same
  /// order.
  List<Role> get assignedAreaRoles => [
    for (final role in user?.assignedRoles ?? const <Role>[])
      if (AppAreas.contains(role.code)) role,
  ];

  bool get canSwitchArea => assignedAreas.length > 1;

  /// The active area: the remembered/selected one while it is still assigned,
  /// otherwise the only assigned area. Null when the account holds several
  /// areas and has chosen none, or holds none at all.
  ///
  /// UI state, never authority: the server still decides what the active area
  /// may DO, and a role taken away stops being selectable here at once.
  String? get activeArea {
    final areas = assignedAreas;
    if (areas.isEmpty) return null;
    final chosen = _activeArea;
    if (chosen != null && areas.contains(chosen)) return chosen;
    return areas.length == 1 ? areas.single : null;
  }

  /// True when the account holds several areas and none is active yet, which
  /// is exactly when the picker has to answer before any screen opens.
  bool get needsAreaChoice => assignedAreas.length > 1 && activeArea == null;

  /// The server role name of the ACTIVE area, or null when there is none.
  ///
  /// Nullable on purpose: `GET /auth/me/` really answers `role: null` for a
  /// groupless account, and [AppRoutes.redirectFor] turns that into the
  /// unsupported-role screen — never a dashboard and never a silent bounce to
  /// the login form (decision 04). The same holds for an account with an empty
  /// `roles[]`: CPMS and role-less accounts have no POS area.
  String? get roleName => activeArea;

  /// Makes [code] the active area, remembering it for this account.
  ///
  /// A code the server does not assign is refused outright and NOT stored: a
  /// stale preference must never be the reason a screen opens.
  Future<void> selectArea(String code) async {
    if (!assignedAreas.contains(code)) return;
    if (_activeArea == code) return;
    _activeArea = code;
    notifyListeners();
    final accountId = user?.id;
    if (accountId != null) await _areas.writeArea(accountId, code);
  }

  /// The first call's restore, shared by every later caller.
  Future<void>? _initialization;

  /// Which restore may still publish its result.
  ///
  /// Bumped when a restore is abandoned (the splash's timeout) or replaced by a
  /// sign-in: a restore started under an older generation answers into the
  /// void instead of signing someone in from behind the login form.
  int _restoreGeneration = 0;

  /// Restores the saved session once; further calls await the same future.
  ///
  /// Two callers ask at startup (the router's redirect and the splash), and
  /// a doubled restore means two token reads and two `/auth/me/` calls.
  Future<void> initialize() => _initialization ??= _restoreSession();

  /// Gives up on a restore that never answered (the splash's timeout).
  ///
  /// Startup counts as resolved with no session, so the router stops parking
  /// every location on the splash and the login form is reachable. The restore
  /// keeps running in the background; its late answer is dropped rather than
  /// published, because a user typing their password must not be moved to a
  /// dashboard by a lookup that started before the timeout.
  void abandonRestore() {
    if (!isInitializing) return;
    _restoreGeneration++;
    // A later `initialize()` would otherwise hand back this dead future.
    _initialization = null;
    isInitializing = false;
    notifyListeners();
  }

  Future<void> _restoreSession() async {
    final generation = _restoreGeneration;
    User? restored;
    try {
      // A session already in hand (a warm start) needs no restore.
      restored = user ?? await repository.restoreSession();
    } catch (_) {
      // Secure storage can fail (a missing keychain entitlement on a fresh
      // desktop install, say). Falling back to the login screen beats a blank
      // window: the splash would otherwise wait on `isInitializing` forever.
      restored = null;
    }
    // Abandoned or superseded while it was in flight: say nothing at all.
    if (generation != _restoreGeneration) return;
    _adopt(restored);
    isInitializing = false;
    notifyListeners();
  }

  /// Publishes [account] and restores its remembered area, validated against
  /// the assignment the server just sent.
  ///
  /// Called on every path that sets the account (sign-in and session restore),
  /// so a revoked role or another user's pick can never survive into a screen.
  void _adopt(User? account) {
    user = account;
    _activeArea = null;
    if (account == null) return;
    final stored = _areas.readArea(account.id);
    if (stored != null && assignedAreas.contains(stored)) {
      _activeArea = stored;
    }
  }

  Future<bool> login(String identifier, String password) async {
    // A restore still in flight belongs to a previous session and must not
    // overwrite the account this sign-in is about to set.
    _restoreGeneration++;
    _initialization = null;

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      _adopt(await repository.login(identifier, password));
      return true;
    } on AuthException catch (exception) {
      _adopt(null);
      error = exception.message;
      return false;
    } catch (_) {
      _adopt(null);
      error = 'Something went wrong. Please try again.';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    isLoading = true;
    notifyListeners();
    try {
      await repository.logout();
    } finally {
      // Signing out clears the active user state, including the active area:
      // the next person at this till starts from their own assignment.
      _adopt(null);
      error = null;
      isLoading = false;
      notifyListeners();
    }
  }
}
