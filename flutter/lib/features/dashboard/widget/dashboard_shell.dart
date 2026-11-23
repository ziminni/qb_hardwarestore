import 'dart:async';

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/navigation/merged_sidebar.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/controllers/pos_lock_settings_controller.dart';
import 'package:client/features/pos/widgets/pos_lock_screen_overlay.dart';
import 'package:client/shared/widgets/app_shell.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// The POS (cashier) shell: the shared menu pattern inside [AppShell], grouped.
class DashboardShell extends StatefulWidget {
  const DashboardShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedNavigationIndex,
    required this.navigationItems,
    required this.child,
    this.onNavigationSelected,
    this.scrollable = true,
    this.actions = const [],
    this.loadMarkers = cashierMarkers,
    this.onVerifyUnlockPassword,
    this.lockSettings,
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final List<DashboardNavigationItem> navigationItems;
  final Widget child;
  final ValueChanged<int>? onNavigationSelected;

  /// See [AppShell.scrollable].
  final bool scrollable;

  /// Widgets at the right end of the header (see [AppShell.actions]).
  final List<Widget> actions;

  /// See [AppShell.loadMarkers].
  final Future<Map<int, int>> Function() loadMarkers;

  /// Optional password verifier override (used in tests). Defaults to
  /// [AuthViewmodel.verifyPassword] from the nearest [Provider].
  final Future<String?> Function(String password)? onVerifyUnlockPassword;

  /// Optional auto-lock settings controller (used in tests). Defaults to
  /// [PosLockSettingsController.instance].
  final PosLockSettingsController? lockSettings;

  /// Flat sidebar index of Held transactions, the destination the parked-cart
  /// count belongs to (0 New transaction, 1 Transaction history,
  /// 2 Release materials, 3 Record payment, 4 Held transactions). Shared by
  /// [cashierMarkers] and pinned by `sidebar_pattern_test.dart`.
  static const heldTransactionsIndex = 5;

  /// The cashier groups, by the index each item ALREADY has, derived from
  /// [AppDestinations] (Phase 2 F1).
  ///
  /// The Till menu is append-only and its indexes are pinned by
  /// `sidebar_index_consistency_test.dart`, so a group is expressed as "where it
  /// starts". Grouping therefore cannot renumber a single destination.
  static List<(String, int)> get groups =>
      AppDestinations.groupsFor(AppAreas.pos);

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  bool _locked = false;
  Timer? _inactivityTimer;
  late PosLockSettingsController _lockSettings;
  int _lastSaleLockVersion = 0;

  @override
  void initState() {
    super.initState();
    _lockSettings = widget.lockSettings ?? PosLockSettingsController.instance;
    _lastSaleLockVersion = _lockSettings.saleLockVersion;
    _lockSettings.addListener(_onLockSettingsChanged);
    _lockSettings.load();
    _resetInactivityTimer();
  }

  @override
  void didUpdateWidget(covariant DashboardShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSettings =
        widget.lockSettings ?? PosLockSettingsController.instance;
    if (!identical(nextSettings, _lockSettings)) {
      _lockSettings.removeListener(_onLockSettingsChanged);
      _lockSettings = nextSettings;
      _lastSaleLockVersion = _lockSettings.saleLockVersion;
      _lockSettings.addListener(_onLockSettingsChanged);
      _lockSettings.load();
      _resetInactivityTimer();
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _lockSettings.removeListener(_onLockSettingsChanged);
    super.dispose();
  }

  void _onLockSettingsChanged() {
    if (_lockSettings.saleLockVersion != _lastSaleLockVersion) {
      _lastSaleLockVersion = _lockSettings.saleLockVersion;
      if (!_locked && mounted) {
        _lockNow();
        return;
      }
    }
    _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_locked) return;
    final timeout = _lockSettings.duration;
    if (timeout == null) return;
    _inactivityTimer = Timer(timeout, () {
      if (!mounted || _locked) return;
      setState(() => _locked = true);
    });
  }

  void _lockNow() {
    _inactivityTimer?.cancel();
    setState(() => _locked = true);
  }

  void _unlockNow() {
    setState(() => _locked = false);
    _resetInactivityTimer();
  }

  Future<String?> _verifyPassword(String password) async {
    final override = widget.onVerifyUnlockPassword;
    if (override != null) {
      return override(password);
    }
    try {
      return await context.read<AuthViewmodel>().verifyPassword(password);
    } on ProviderNotFoundException {
      return 'Unable to verify password in this context.';
    }
  }

  String? _accountLabel() {
    try {
      final user = context.watch<AuthViewmodel>().user;
      if (user == null) return null;
      final name = user.fullName.trim();
      return name.isNotEmpty ? name : user.username;
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final headerActions = <Widget>[
      ...widget.actions,
      IconButton(
        key: const ValueKey('pos-header-lock-button'),
        tooltip: 'Lock screen',
        onPressed: _lockNow,
        icon: const Icon(
          Icons.lock_outline_rounded,
          color: AppColors.textSecondary,
          size: 20,
        ),
      ),
    ];

    return CallbackShortcuts(
      bindings: {
        if (!_locked && _lockSettings.lockShortcutEnabled) ...{
          const SingleActivator(LogicalKeyboardKey.keyL, control: true):
              _lockNow,
          const SingleActivator(LogicalKeyboardKey.keyL, meta: true): _lockNow,
        },
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _resetInactivityTimer(),
        onPointerSignal: (_) => _resetInactivityTimer(),
        child: Stack(
          children: [
            AppShell(
              title: widget.title,
              subtitle: widget.subtitle,
              sections: _sectionsFor(widget.navigationItems),
              selectedIndex: widget.selectedNavigationIndex,
              originArea: AppAreas.pos,
              onDestinationSelected: widget.onNavigationSelected,
              scrollable: widget.scrollable,
              actions: headerActions,
              loadMarkers: widget.loadMarkers,
              child: widget.child,
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !_locked,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                  child: _locked
                      ? PosLockScreenOverlay(
                          key: const ValueKey('pos-lock-overlay-active'),
                          accountLabel: _accountLabel(),
                          onVerifyPassword: _verifyPassword,
                          onUnlocked: _unlockNow,
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('pos-lock-overlay-idle'),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<SharedSidebarSection> _sectionsFor(
    List<DashboardNavigationItem> items,
  ) {
    final sections = <SharedSidebarSection>[];
    final groups = DashboardShell.groups;
    for (var group = 0; group < groups.length; group++) {
      final start = groups[group].$2;
      if (start >= items.length) break;
      final nextStart = group + 1 < groups.length
          ? groups[group + 1].$2
          : items.length;
      final end = nextStart > items.length ? items.length : nextStart;
      sections.add(
        SharedSidebarSection(
          label: groups[group].$1,
          destinations: [
            for (final item in items.sublist(start, end))
              SharedSidebarDestination(label: item.label, icon: item.icon),
          ],
        ),
      );
    }
    return sections;
  }
}

class DashboardNavigationItem {
  const DashboardNavigationItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Parked baskets, the one live count on the cashier menu (ledger ruling, F4):
/// held transactions at index 4. Read once when the shell mounts; a failure
/// shows no marker rather than a false 0.
Future<Map<int, int>> cashierMarkers() async {
  final count = await heldCartsCount();
  return {DashboardShell.heldTransactionsIndex: count};
}
