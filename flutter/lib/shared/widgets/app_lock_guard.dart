import 'dart:async';

import 'package:client/core/constants/app_colors.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_lock_screen_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Wraps a role shell with manual lock, `Ctrl+L` / `Cmd+L` quick-lock, and an
/// optional inactivity auto-lock timer, showing [PosLockScreenOverlay].
class AppLockGuard extends StatefulWidget {
  const AppLockGuard({
    super.key,
    required this.listenable,
    required this.autoLockDuration,
    required this.shortcutEnabled,
    required this.builder,
    this.onVerifyUnlockPassword,
  });

  final Listenable listenable;
  final Duration? Function() autoLockDuration;
  final bool Function() shortcutEnabled;
  final Widget Function(BuildContext context, VoidCallback lockNow) builder;
  final Future<String?> Function(String password)? onVerifyUnlockPassword;

  /// Shared header lock icon button used across role shells.
  static Widget lockIconButton({
    required Key key,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      key: key,
      tooltip: 'Lock screen',
      onPressed: onPressed,
      icon: const Icon(
        Icons.lock_outline_rounded,
        color: AppColors.textSecondary,
        size: 20,
      ),
    );
  }

  @override
  State<AppLockGuard> createState() => _AppLockGuardState();
}

class _AppLockGuardState extends State<AppLockGuard> {
  bool _locked = false;
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    widget.listenable.addListener(_onSettingsChanged);
    _resetInactivityTimer();
  }

  @override
  void didUpdateWidget(covariant AppLockGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.listenable, oldWidget.listenable)) {
      oldWidget.listenable.removeListener(_onSettingsChanged);
      widget.listenable.addListener(_onSettingsChanged);
      _resetInactivityTimer();
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    widget.listenable.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_locked) return;
    final timeout = widget.autoLockDuration();
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
    if (override != null) return override(password);
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
    return ListenableBuilder(
      listenable: widget.listenable,
      builder: (context, _) {
        final shortcutsActive = !_locked && widget.shortcutEnabled();
        return CallbackShortcuts(
          bindings: {
            if (shortcutsActive) ...{
              const SingleActivator(LogicalKeyboardKey.keyL, control: true):
                  _lockNow,
              const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
                  _lockNow,
            },
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _resetInactivityTimer(),
            onPointerSignal: (_) => _resetInactivityTimer(),
            child: Stack(
              children: [
                widget.builder(context, _lockNow),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !_locked,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: _locked
                          ? PosLockScreenOverlay(
                              key: const ValueKey('app-lock-overlay-active'),
                              accountLabel: _accountLabel(),
                              onVerifyPassword: _verifyPassword,
                              onUnlocked: _unlockNow,
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('app-lock-overlay-idle'),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
