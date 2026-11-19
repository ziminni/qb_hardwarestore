import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/data/services/system_admin_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// A signed-in staff session record, shaped to bind cleanly to a future
/// `GET /api/v1/auth/sessions/` endpoint.
class ActiveSessionRecord {
  const ActiveSessionRecord({
    required this.id,
    required this.fullName,
    required this.username,
    required this.roleLabel,
    required this.deviceLabel,
    required this.ipAddress,
    required this.lastSeenAt,
    this.isCurrentDevice = false,
  });

  final String id;
  final String fullName;
  final String username;
  final String roleLabel;
  final String deviceLabel;
  final String ipAddress;
  final DateTime lastSeenAt;
  final bool isCurrentDevice;
}

/// A sign-in or failed-login event, shaped for a future login-audit endpoint.
class LoginActivityRecord {
  const LoginActivityRecord({
    required this.id,
    required this.username,
    required this.deviceLabel,
    required this.ipAddress,
    required this.timestamp,
    required this.succeeded,
    this.note = '',
  });

  final String id;
  final String username;
  final String deviceLabel;
  final String ipAddress;
  final DateTime timestamp;
  final bool succeeded;
  final String note;
}

/// Admin -> Active Sessions & Security (`/admin/security`).
///
/// Frontend-only governance workspace showing the real currently signed-in
/// device from [AuthViewmodel], plus searchable Active Sessions, Security
/// Policies, and Sign-in Activity panels ready to bind to backend session
/// endpoints once enabled.
class AdminSecurityPage extends StatefulWidget {
  const AdminSecurityPage({
    super.key,
    this.initialSessions = const [],
    this.initialLoginEvents = const [],
    this.service,
  });

  final List<ActiveSessionRecord> initialSessions;
  final List<LoginActivityRecord> initialLoginEvents;
  final SystemAdminService? service;

  @override
  State<AdminSecurityPage> createState() => _AdminSecurityPageState();
}

class _AdminSecurityPageState extends State<AdminSecurityPage> {
  late final SystemAdminService _service =
      widget.service ?? const SystemAdminService();

  late List<ActiveSessionRecord> _sessions = [...widget.initialSessions];
  late List<LoginActivityRecord> _loginEvents = [...widget.initialLoginEvents];
  bool _serverConnected = false;

  // ---- Session filters
  final TextEditingController _sessionSearch = TextEditingController();
  String _sessionQuery = '';
  String _sessionRoleFilter = 'All roles';

  // ---- Login activity filters
  final TextEditingController _eventSearch = TextEditingController();
  String _eventQuery = '';
  String _eventOutcomeFilter = 'All';

  // ---- Security policy draft
  int _minPasswordLength = 8;
  String _idleTimeout = '30 min';
  int _lockoutThreshold = 5;
  bool _requireManagerOverride = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadFromServer();
    });
  }

  Future<void> _loadFromServer() async {
    try {
      final overview = await _service.fetchSecurityOverview();
      if (!mounted) return;
      setState(() {
        _serverConnected = true;
        _minPasswordLength = overview.policy.minPasswordLength;
        _idleTimeout = overview.policy.idleTimeout;
        _lockoutThreshold = overview.policy.lockoutThreshold;
        _requireManagerOverride = overview.policy.requireManagerOverride;
        if (widget.initialSessions.isEmpty || overview.sessions.isNotEmpty) {
          _sessions = overview.sessions;
        }
        if (widget.initialLoginEvents.isEmpty ||
            overview.loginEvents.isNotEmpty) {
          _loginEvents = overview.loginEvents;
        }
      });
    } catch (_) {
      // Offline / uninitialized transport in isolated widget tests: keep
      // initialSessions and initialLoginEvents intact.
    }
  }

  Future<void> _syncPolicy() async {
    try {
      final saved = await _service.updateSecurityPolicy(
        SecurityPolicyState(
          minPasswordLength: _minPasswordLength,
          idleTimeout: _idleTimeout,
          lockoutThreshold: _lockoutThreshold,
          requireManagerOverride: _requireManagerOverride,
        ),
      );
      if (!mounted) return;
      setState(() {
        _serverConnected = true;
        _minPasswordLength = saved.minPasswordLength;
        _idleTimeout = saved.idleTimeout;
        _lockoutThreshold = saved.lockoutThreshold;
        _requireManagerOverride = saved.requireManagerOverride;
      });
    } catch (_) {
      // Ignore in offline unit tests.
    }
  }

  @override
  void dispose() {
    _sessionSearch.dispose();
    _eventSearch.dispose();
    super.dispose();
  }

  List<String> get _sessionRoles {
    final found = {for (final s in _sessions) s.roleLabel}.toList()..sort();
    return ['All roles', ...found];
  }

  List<ActiveSessionRecord> get _filteredSessions {
    final q = _sessionQuery.trim().toLowerCase();
    return [
      for (final s in _sessions)
        if ((_sessionRoleFilter == 'All roles' ||
                s.roleLabel == _sessionRoleFilter) &&
            (q.isEmpty ||
                '${s.fullName} ${s.username} ${s.deviceLabel} ${s.ipAddress}'
                    .toLowerCase()
                    .contains(q)))
          s,
    ];
  }

  List<LoginActivityRecord> get _filteredEvents {
    final q = _eventQuery.trim().toLowerCase();
    return [
      for (final e in _loginEvents)
        if ((_eventOutcomeFilter == 'All' ||
                (_eventOutcomeFilter == 'Succeeded' && e.succeeded) ||
                (_eventOutcomeFilter == 'Failed' && !e.succeeded)) &&
            (q.isEmpty ||
                '${e.username} ${e.deviceLabel} ${e.ipAddress} ${e.note}'
                    .toLowerCase()
                    .contains(q)))
          e,
    ];
  }

  String _currentPlatformLabel() {
    if (kIsWeb) return 'Web browser';
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS => 'macOS desktop',
      TargetPlatform.windows => 'Windows desktop',
      TargetPlatform.linux => 'Linux desktop',
      TargetPlatform.android => 'Android device',
      TargetPlatform.iOS => 'iOS device',
      TargetPlatform.fuchsia => 'Desktop client',
    };
  }

  Future<void> _confirmForceSignOut(ActiveSessionRecord session) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final p = AppPalette.of(dialogContext);
        final errorBg = p.isDark
            ? AppColors.error.withValues(alpha: 0.14)
            : AppColors.errorTint;
        final errorInk = p.isDark
            ? const Color(0xFFFCA5A5)
            : AppColors.errorText;

        return AppDialog(
          icon: Icons.logout_rounded,
          title: 'Force sign out ${session.fullName}?',
          subtitle: '${session.username} · ${session.deviceLabel}',
          width: 460,
          content: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: errorBg,
              borderRadius: BorderRadius.circular(AppRadii.medium),
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              'Revoking this session will sign ${session.username} out on '
              '${session.deviceLabel} (${session.ipAddress}). Server execution '
              'activates once POST /api/v1/auth/sessions/revoke/ is connected.',
              style: TextStyle(fontSize: 13, height: 1.45, color: errorInk),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await _service.revokeSession(session.id);
                  if (!mounted) return;
                  setState(() {
                    _sessions.removeWhere((s) => s.id == session.id);
                  });
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Force-signed out ${session.username} (${session.deviceLabel}).',
                      ),
                    ),
                  );
                  await _loadFromServer();
                } catch (_) {
                  if (!mounted) return;
                  setState(() {
                    _sessions.removeWhere((s) => s.id == session.id);
                  });
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        'Revoked session for ${session.username}.',
                      ),
                    ),
                  );
                }
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: AppColors.brandWhite,
              ),
              child: const Text('Force sign out'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmCurrentSignOut(AuthViewmodel auth) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AppDialog(
        icon: Icons.logout_rounded,
        title: 'Sign out of this device?',
        subtitle: 'You will return to the login screen immediately.',
        width: 420,
        content: const Text(
          'Your local JWT tokens will be cleared from this device.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              auth.logout();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.brandWhite,
            ),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final auth = context.watch<AuthViewmodel>();
    final user = auth.user;
    final sessions = _filteredSessions;
    final events = _filteredEvents;
    final hasSessionFilter =
        _sessionQuery.trim().isNotEmpty || _sessionRoleFilter != 'All roles';
    final hasEventFilter =
        _eventQuery.trim().isNotEmpty || _eventOutcomeFilter != 'All';

    return AdminSkeletonLayout(
      title: 'Active Sessions & Security',
      subtitle: 'Monitor signed-in devices, login attempts, and access rules.',
      selectedNavigationIndex: AppDestinations.indexOf(
        'admin.security',
        AppAreas.admin,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Readiness & quick navigation banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: p.cardBackground,
              borderRadius: BorderRadius.circular(AppRadii.large),
              border: Border.all(color: p.accent.withValues(alpha: 0.45)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: p.selected,
                          borderRadius: BorderRadius.circular(AppRadii.medium),
                          border: Border.all(
                            color: p.accent.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Icon(
                          Icons.security_outlined,
                          size: 20,
                          color: p.accentInk,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Session & access control',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: p.textPrimary,
                                  ),
                                ),
                                StatusBadge(
                                  label: _serverConnected
                                      ? 'Live server sync'
                                      : 'Awaiting sessions API',
                                  tone: _serverConnected
                                      ? StatusTone.success
                                      : StatusTone.info,
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'This device\'s live session is shown below. '
                              'Multi-device tracking, remote sign-out, and '
                              'failed login logs activate once the backend '
                              'sessions endpoints are wired.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.45,
                                color: p.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          GoRouter.maybeOf(context)?.go(AppRoutes.adminAuditLogs),
                      icon: const Icon(Icons.history_rounded, size: 16),
                      label: const Text('Audit logs'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => GoRouter.maybeOf(
                        context,
                      )?.go(AppRoutes.adminUserManagement),
                      icon: const Icon(
                        Icons.manage_accounts_outlined,
                        size: 16,
                      ),
                      label: const Text('User management'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Current device live session + security policy cards
          LayoutBuilder(
            builder: (context, constraints) {
              final twoColumn = constraints.maxWidth >= 880;
              final currentSessionCard = _CurrentDeviceCard(
                fullName: user?.fullName ?? 'Administrator',
                username: user?.username ?? 'admin',
                roleLabel: user?.roleLabel ?? 'Admin',
                platformLabel: _currentPlatformLabel(),
                onSignOut: () => _confirmCurrentSignOut(auth),
              );
              final policyCard = _SecurityPolicyCard(
                minPasswordLength: _minPasswordLength,
                idleTimeout: _idleTimeout,
                lockoutThreshold: _lockoutThreshold,
                requireManagerOverride: _requireManagerOverride,
                serverConnected: _serverConnected,
                onMinPasswordLengthChanged: (v) {
                  setState(() => _minPasswordLength = v);
                  _syncPolicy();
                },
                onIdleTimeoutChanged: (v) {
                  setState(() => _idleTimeout = v);
                  _syncPolicy();
                },
                onLockoutThresholdChanged: (v) {
                  setState(() => _lockoutThreshold = v);
                  _syncPolicy();
                },
                onRequireManagerOverrideChanged: (v) {
                  setState(() => _requireManagerOverride = v);
                  _syncPolicy();
                },
              );

              if (twoColumn) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: currentSessionCard),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: policyCard),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  currentSessionCard,
                  const SizedBox(height: AppSpacing.lg),
                  policyCard,
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),

          // Active Sessions & Devices
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.cardBackground,
              borderRadius: BorderRadius.circular(AppRadii.large),
              border: Border.all(color: p.border),
            ),
            child: FilterBar(
              searchController: _sessionSearch,
              searchHint: 'Search active sessions by staff, device, or IP',
              onSearchChanged: (v) => setState(() => _sessionQuery = v),
              optionsLabel: 'Role',
              options: _sessionRoles,
              selected: _sessionRoleFilter,
              onSelected: (v) => setState(() => _sessionRoleFilter = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DataPanel<ActiveSessionRecord>(
            title: 'Active sessions across devices',
            count: sessions.length,
            rows: sessions,
            emptyMessage: hasSessionFilter
                ? 'No active sessions match these filters.'
                : 'No remote sessions reported yet. Signed-in POS terminals '
                      'and staff devices will list here once the server '
                      'session registry endpoint is connected.',
            rowKey: (s) => ValueKey('admin.session.${s.id}'),
            columns: [
              DataPanelColumn<ActiveSessionRecord>(
                label: 'Account',
                flex: 3,
                cell: (s) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${s.username} · ${s.roleLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              DataPanelColumn<ActiveSessionRecord>(
                label: 'Device & IP',
                flex: 3,
                cell: (s) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.deviceLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    Text(
                      s.ipAddress,
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              DataPanelColumn<ActiveSessionRecord>(
                label: 'Last active',
                flex: 2,
                cell: (s) => Text(
                  formatDate(s.lastSeenAt),
                  style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                ),
              ),
              DataPanelColumn<ActiveSessionRecord>(
                label: 'Action',
                flex: 2,
                cell: (s) => s.isCurrentDevice
                    ? const StatusBadge(
                        label: 'This device',
                        tone: StatusTone.success,
                      )
                    : TextButton.icon(
                        onPressed: () => _confirmForceSignOut(s),
                        style: TextButton.styleFrom(
                          backgroundColor: p.isDark
                              ? AppColors.error.withValues(alpha: 0.16)
                              : AppColors.errorTint,
                          foregroundColor: p.isDark
                              ? const Color(0xFFFCA5A5)
                              : AppColors.errorText,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          minimumSize: const Size(44, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadii.small),
                            side: BorderSide(
                              color: AppColors.error.withValues(alpha: 0.28),
                            ),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        icon: const Icon(Icons.logout_rounded, size: 15),
                        label: const Text('Force sign out'),
                      ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),

          // Login & failed-attempt log
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.cardBackground,
              borderRadius: BorderRadius.circular(AppRadii.large),
              border: Border.all(color: p.border),
            ),
            child: FilterBar(
              searchController: _eventSearch,
              searchHint: 'Search login events by username, device, or IP',
              onSearchChanged: (v) => setState(() => _eventQuery = v),
              optionsLabel: 'Outcome',
              options: const ['All', 'Succeeded', 'Failed'],
              selected: _eventOutcomeFilter,
              onSelected: (v) => setState(() => _eventOutcomeFilter = v),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          DataPanel<LoginActivityRecord>(
            title: 'Login & failed-attempt log',
            count: events.length,
            rows: events,
            emptyMessage: hasEventFilter
                ? 'No login events match these filters.'
                : 'No sign-in events recorded yet. Successful and failed login '
                      'attempts will appear here once the login-audit endpoint '
                      'is connected.',
            rowKey: (e) => ValueKey('admin.login-event.${e.id}'),
            columns: [
              DataPanelColumn<LoginActivityRecord>(
                label: 'Username',
                flex: 2,
                cell: (e) => Text(
                  e.username,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.textPrimary,
                  ),
                ),
              ),
              DataPanelColumn<LoginActivityRecord>(
                label: 'Outcome',
                flex: 2,
                cell: (e) => StatusBadge(
                  label: e.succeeded ? 'Succeeded' : 'Failed',
                  tone: e.succeeded ? StatusTone.success : StatusTone.error,
                ),
              ),
              DataPanelColumn<LoginActivityRecord>(
                label: 'Device & IP',
                flex: 3,
                cell: (e) => Text(
                  '${e.deviceLabel} · ${e.ipAddress}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                ),
              ),
              DataPanelColumn<LoginActivityRecord>(
                label: 'Time',
                flex: 2,
                cell: (e) => Text(
                  formatDate(e.timestamp),
                  style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentDeviceCard extends StatelessWidget {
  const _CurrentDeviceCard({
    required this.fullName,
    required this.username,
    required this.roleLabel,
    required this.platformLabel,
    required this.onSignOut,
  });

  final String fullName;
  final String username;
  final String roleLabel;
  final String platformLabel;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      key: const ValueKey('security-current-device'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: p.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const HexIconBadge(icon: Icons.devices_outlined, size: 42),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This device',
                      style: AppTextStyles.h3.copyWith(
                        fontSize: 18,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Currently authenticated Admin session.',
                      style: TextStyle(fontSize: 12.5, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              const StatusBadge(label: 'Active', tone: StatusTone.success),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          const DialogSectionLabel('Session details'),
          _DetailRow(label: 'Signed in as', value: '$fullName ($username)'),
          _DetailRow(label: 'Role', value: roleLabel),
          _DetailRow(label: 'Client', value: platformLabel),
          _DetailRow(
            label: 'Token storage',
            value: 'Encrypted local JWT + automatic 401 refresh',
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            key: const ValueKey('security-signout-current'),
            onPressed: onSignOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: p.isDark
                  ? const Color(0xFFFCA5A5)
                  : AppColors.errorText,
              side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
              minimumSize: const Size(double.infinity, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.medium),
              ),
            ),
            icon: const Icon(Icons.logout_rounded, size: 17),
            label: const Text('Sign out this device'),
          ),
        ],
      ),
    );
  }
}

class _SecurityPolicyCard extends StatelessWidget {
  const _SecurityPolicyCard({
    required this.minPasswordLength,
    required this.idleTimeout,
    required this.lockoutThreshold,
    required this.requireManagerOverride,
    this.serverConnected = false,
    required this.onMinPasswordLengthChanged,
    required this.onIdleTimeoutChanged,
    required this.onLockoutThresholdChanged,
    required this.onRequireManagerOverrideChanged,
  });

  final int minPasswordLength;
  final String idleTimeout;
  final int lockoutThreshold;
  final bool requireManagerOverride;
  final bool serverConnected;
  final ValueChanged<int> onMinPasswordLengthChanged;
  final ValueChanged<String> onIdleTimeoutChanged;
  final ValueChanged<int> onLockoutThresholdChanged;
  final ValueChanged<bool> onRequireManagerOverrideChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      key: const ValueKey('security-policy-card'),
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: p.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 20, color: p.accentInk),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Password & session policy',
                    style: AppTextStyles.h3.copyWith(
                      fontSize: 17,
                      color: p.textPrimary,
                    ),
                  ),
                ],
              ),
              StatusBadge(
                label: serverConnected ? 'Synced with server' : 'Pending server sync',
                tone: serverConnected ? StatusTone.success : StatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          _PolicyChoiceGroup<int>(
            label: 'MINIMUM PASSWORD LENGTH',
            options: const [8, 10, 12],
            selected: minPasswordLength,
            labelOf: (v) => '$v chars',
            onSelected: onMinPasswordLengthChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          _PolicyChoiceGroup<String>(
            label: 'IDLE SESSION TIMEOUT',
            options: const ['15 min', '30 min', '1 hour', '4 hours'],
            selected: idleTimeout,
            labelOf: (v) => v,
            onSelected: onIdleTimeoutChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          _PolicyChoiceGroup<int>(
            label: 'FAILED LOGIN LOCKOUT',
            options: const [5, 10],
            selected: lockoutThreshold,
            labelOf: (v) => '$v attempts',
            onSelected: onLockoutThresholdChanged,
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: p.border),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manager approval for high discounts',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Require Store Manager approval above the cashier cap.',
                      style: TextStyle(fontSize: 12, color: p.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(
                value: requireManagerOverride,
                onChanged: onRequireManagerOverrideChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PolicyChoiceGroup<T> extends StatelessWidget {
  const _PolicyChoiceGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String label;
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(labelOf(option)),
                selected: option == selected,
                backgroundColor: p.surfaceSunken,
                selectedColor: p.selected,
                checkmarkColor: p.accentInk,
                side: BorderSide(
                  color: option == selected ? p.accent : p.border,
                ),
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: option == selected ? p.accentInk : p.textPrimary,
                ),
                onSelected: (_) => onSelected(option),
              ),
          ],
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: p.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: p.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
