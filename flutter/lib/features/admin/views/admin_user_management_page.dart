import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/data/models/user.dart';
import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:client/features/admin/widgets/admin_user_action_button.dart';
import 'package:client/features/admin/widgets/admin_user_table.dart';
import 'package:client/features/admin/widgets/roles_permissions_dialog.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The admin User Management screen, also the Store Manager's Staff screen.
///
/// Lists staff accounts with the server-computed totals, narrows them by search
/// and role/status chips, creates accounts through the register shape (admins
/// only: creation stays Admin-only server-side), and offers deactivate/reactivate
/// plus role change per row (Phase 5: Store Managers act on non-admin staff; the
/// server refuses admin-bound changes with 403 `USER_ADMIN_FORBIDDEN` and the
/// last-admin strip with 400 `LAST_ADMIN`, both shown in the page banner).
/// Role identity is compared by GROUP name (what `assign_role` takes), never by
/// display label or client role code.
///
/// Layout: one summary line replaces the four metric cards (a list of a handful
/// of people was spending more screen on its totals than on the people), and the
/// rows are a `DataPanel` inside an `Expanded`, so a long list builds only the
/// rows on screen and a 760 px window gets cards with the actions inside them.
class AdminUserManagementPage extends StatefulWidget {
  const AdminUserManagementPage({
    super.key,
    this.viewmodel,
    this.inSalesShell = false,
  });

  /// Draw inside the Store Manager's shell (sales sidebar, index 8) instead of
  /// the admin one. See `SalesStaffPage`.
  final bool inSalesShell;

  /// Injected by tests so the load path can be driven WITHOUT a server.
  final AdminUsersViewmodel? viewmodel;

  @override
  State<AdminUserManagementPage> createState() =>
      _AdminUserManagementPageState();
}

class _AdminUserManagementPageState extends State<AdminUserManagementPage> {
  /// The chip that filters nothing.
  static const String _anyRole = 'All roles';
  static const String _anyStatus = 'All statuses';

  /// The search text. Narrows the rows already loaded, so typing costs no
  /// request and the reader sees the list shrink as they type.
  String _query = '';

  /// Owned here, not by the bar, so "Clear filters" can empty the field too.
  final TextEditingController _searchController = TextEditingController();

  /// The rows' scroll position, so a wheel that lands on the header still
  /// moves them. The page lays out its own scrolling regions
  /// (`scrollable: false`: the list builds rows lazily inside an `Expanded`),
  /// which leaves the summary, the search field and the wrapped chip rows — a
  /// third of a 760 x 900 window — with no scrollable at all. A wheel there
  /// moved nothing, and the accounts below the fold looked unreachable
  /// (QA wave 3b).
  final ScrollController _listScroll = ScrollController();

  @override
  void dispose() {
    _searchController.dispose();
    _listScroll.dispose();
    super.dispose();
  }

  /// Hands a wheel that landed OUTSIDE the list to the list.
  ///
  /// Pointer signals are resolved deepest-first, so a wheel over the rows still
  /// reaches their own `Scrollable`; only the rest of the page arrives here.
  /// [ScrollPosition.pointerScroll] is the same call the framework makes for a
  /// wheel over a scroll view, so the rows move with the same physics.
  void _forwardWheelToRows(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (!_listScroll.hasClients) return;
      _listScroll.position.pointerScroll(
        (event as PointerScrollEvent).scrollDelta.dy,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Page-scoped viewmodel: loaded in create (no listeners attached yet, so
    // the first notify is harmless) — the reports page's established pattern.
    // initState cannot read a provider this page itself creates.
    return ChangeNotifierProvider(
      create: (_) => (widget.viewmodel ?? AdminUsersViewmodel())..load(),
      child: Builder(
        builder: (context) {
          final viewmodel = context.watch<AdminUsersViewmodel>();
          // Role CODE comparison (Phase 4 lesson): the server sends codes
          // ('admin', 'sales', ...); display labels belong on screen only.
          // Holds Admin, not "is working in Admin" (Phase 2 F3).
          final isAdmin = context.read<AuthViewmodel>().hasArea('admin');
          final content = _body(context, viewmodel, isAdmin: isAdmin);
          const subtitle = 'View and manage staff accounts.';
          if (widget.inSalesShell) {
            return SalesSkeletonLayout(
              title: 'Staff',
              subtitle: subtitle,
              // Looked up, never literal: Quotations occupied 2 until its
              // hide shifted every later row (Staff 7 -> 6).
              selectedNavigationIndex: AppDestinations.indexOf(
                'staff',
                AppAreas.sales,
              ),
              onNavigationSelected: (index) => navigateSales(context, index),
              // The list owns its scrolling: `Expanded` below needs a bounded
              // body, and a long list must build only the rows on screen.
              scrollable: false,
              child: content,
            );
          }
          return AdminSkeletonLayout(
            title: 'User Management',
            subtitle: subtitle,
            selectedNavigationIndex: AppDestinations.indexOf(
              'staff',
              AppAreas.admin,
            ),
            scrollable: false,
            child: content,
          );
        },
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AdminUsersViewmodel viewmodel, {
    required bool isAdmin,
  }) {
    final p = AppPalette.of(context);
    final currentUser = context.watch<AuthViewmodel>().user;
    final stats = viewmodel.stats;
    // A FIRST read that failed is one banner: the rows below it would be an
    // empty panel, and a zero summary would claim the store has no staff.
    final firstLoadFailed = !viewmodel.hasLoaded && viewmodel.loadError != null;
    final rows = _matchingQuery(viewmodel.users);
    final filtered =
        _query.trim().isNotEmpty ||
        viewmodel.roleFilter != null ||
        viewmodel.activeFilter != null;
    // Fewer rows than the server counts is what "hidden by a filter" means; the
    // way back only earns its place when something is actually missing.
    final filtersHideRows =
        filtered && rows.length < (stats?.total ?? viewmodel.users.length);

    return Listener(
      onPointerSignal: _forwardWheelToRows,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              // The summary strip: absent until the server has answered, so a
              // failed first load never claims the store has zero staff.
              if (stats != null)
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: p.cardBackground,
                        borderRadius: BorderRadius.circular(AppRadii.medium),
                        border: Border.all(color: p.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: p.selected,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Icon(
                              Icons.groups_2_outlined,
                              size: 14,
                              color: p.accentInk,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              _summary(stats),
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: p.textPrimary,
                                height: 1.35,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (filtersHideRows)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: p.selected,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(
                            color: p.accent.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          'Showing ${formatCount(rows.length)} of '
                          '${formatCount(stats.total)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.accentInk,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                  ],
                )
              else
                const SizedBox.shrink(),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  // FX5: beside the summary, so a reader who wonders where the
                  // other accounts went has one obvious way back.
                  if (filtersHideRows)
                    TextButton.icon(
                      onPressed: () => _clearFilters(viewmodel),
                      style: TextButton.styleFrom(
                        foregroundColor: p.accentInk,
                        backgroundColor: p.selected,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        minimumSize: const Size(0, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.medium),
                          side: BorderSide(
                            color: p.accent.withValues(alpha: 0.45),
                          ),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      icon: const Icon(
                        Icons.filter_alt_off_outlined,
                        size: 16,
                      ),
                      label: const Text('Clear filters'),
                    ),
                  SizedBox(
                    width: 42,
                    height: 42,
                    child: IconButton(
                      key: const ValueKey('user-management-roles-help'),
                      tooltip: 'Roles & permissions guide',
                      onPressed: () => showRolesPermissionsDialog(context),
                      style: IconButton.styleFrom(
                        backgroundColor: p.cardBackground,
                        foregroundColor: p.accentInk,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.medium),
                          side: BorderSide(color: p.border),
                        ),
                      ),
                      icon: const Icon(Icons.help_outline_rounded, size: 19),
                    ),
                  ),
                  if (!firstLoadFailed)
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: IconButton(
                        tooltip: 'Refresh staff list',
                        onPressed: viewmodel.isLoading ? null : viewmodel.load,
                        style: IconButton.styleFrom(
                          backgroundColor: p.cardBackground,
                          foregroundColor: p.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppRadii.medium,
                            ),
                            side: BorderSide(color: p.border),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 19),
                      ),
                    ),
                  // Creation stays Admin-only server-side (`register_view` is
                  // `IsAdminRole`), so non-admins are not offered it.
                  if (isAdmin)
                    AdminUserActionButton(
                      label: 'Create account',
                      icon: Icons.person_add_outlined,
                      onPressed: () => _openCreateDialog(
                        context,
                        viewmodel,
                        isAdmin: isAdmin,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (firstLoadFailed)
            ErrorBanner(message: viewmodel.loadError!, onRetry: viewmodel.load)
          else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: p.cardBackground,
                borderRadius: BorderRadius.circular(AppRadii.large),
                border: Border.all(color: p.border),
              ),
              child: FilterBar(
                searchController: _searchController,
                searchHint: 'Search name, username, or email',
                onSearchChanged: (value) => setState(() => _query = value),
                // Only the roles the loaded rows actually carry, plus "No role":
                // filtering to a group nobody has would be an empty promise.
                optionsLabel: 'Role',
                options: [_anyRole, ...viewmodel.availableRoles],
                selected: viewmodel.roleFilter ?? _anyRole,
                onSelected: (chip) =>
                    viewmodel.setRoleFilter(chip == _anyRole ? null : chip),
                extraOptionsLabel: 'Status',
                extraOptions: const [_anyStatus, 'Active', 'Inactive'],
                extraSelected: switch (viewmodel.activeFilter) {
                  true => 'Active',
                  false => 'Inactive',
                  null => _anyStatus,
                },
                onExtraSelected: (chip) =>
                    viewmodel.setActiveFilter(switch (chip) {
                      'Active' => true,
                      'Inactive' => false,
                      _ => null,
                    }),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // A refused write (403 USER_ADMIN_FORBIDDEN, 400 LAST_ADMIN) names
            // itself here, above the rows it did not change.
            if (viewmodel.actionError != null) ...[
              ErrorBanner(
                message: viewmodel.actionError!,
                onRetry: viewmodel.clearActionError,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            // A refresh that failed under rows already read: the rows are still
            // the server's last answer, so they stay and the banner explains.
            if (viewmodel.hasLoaded && viewmodel.loadError != null) ...[
              ErrorBanner(
                message: viewmodel.loadError!,
                onRetry: viewmodel.load,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Expanded(
              child: AdminUserTable(
                users: rows,
                controller: _listScroll,
                // Authority comes from the viewer's role CODE, not a label: the
                // server refuses a non-admin's write on an admin account with
                // 403 USER_ADMIN_FORBIDDEN, so the actions are not offered there.
                isAdminViewer: isAdmin,
                currentUserId: currentUser?.id,
                currentUsername: currentUser?.username,
                emptyMessage: filtered
                    ? 'No accounts match these filters.'
                    : 'No staff accounts yet.',
                // Only a first read may take the slot: a refresh keeps its rows.
                isLoading: viewmodel.isLoading && !viewmodel.hasLoaded,
                onToggleActive: (user) =>
                    _openToggleDialog(context, viewmodel, user),
                onChangeRole: (user) => _openRoleDialog(
                  context,
                  viewmodel,
                  user,
                  isAdmin: isAdmin,
                  currentUser: currentUser,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Puts the whole loaded list back: the search field, the chips, and the
  /// rows the server holds (the reload is the viewmodel's own path).
  void _clearFilters(AdminUsersViewmodel viewmodel) {
    _searchController.clear();
    setState(() => _query = '');
    viewmodel.clearFilters();
  }

  /// `12 accounts, 10 active, 2 inactive` (D7: grouped counts).
  ///
  /// The words match the row badges on purpose: one word per state per screen.
  static String _summary(UserStats stats) {
    final accounts = stats.total == 1 ? 'account' : 'accounts';
    return '${formatCount(stats.total)} $accounts, '
        '${formatCount(stats.active)} active, '
        '${formatCount(stats.inactive)} inactive';
  }

  /// The rows whose name, username or email contains the search text.
  ///
  /// Client-side: `fetchUsers` reads one server page, so a server search would
  /// only ever match what one page already holds. (Reported: the read must move
  /// to every-page before this list can be searched server-side.)
  List<User> _matchingQuery(List<User> rows) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return [
      for (final user in rows)
        if ('${user.fullName} ${user.username} ${user.email}'
            .toLowerCase()
            .contains(query))
          user,
    ];
  }

  Future<void> _openCreateDialog(
    BuildContext context,
    AdminUsersViewmodel viewmodel, {
    required bool isAdmin,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) =>
          _CreateAccountDialog(viewmodel: viewmodel, isAdminViewer: isAdmin),
    );
  }

  /// Deactivate/reactivate confirm. Nothing is written until Confirm: the
  /// refusal (LAST_ADMIN, USER_ADMIN_FORBIDDEN) surfaces in the page banner
  /// via [AdminUsersViewmodel.actionError], not inside this dialog.
  Future<void> _openToggleDialog(
    BuildContext context,
    AdminUsersViewmodel viewmodel,
    User user,
  ) {
    final verb = user.isActive ? 'Deactivate' : 'Reactivate';
    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final p = AppPalette.of(dialogContext);
        final isDeactivate = user.isActive;
        final calloutBg = isDeactivate
            ? (p.isDark
                  ? AppColors.error.withValues(alpha: 0.14)
                  : AppColors.errorTint)
            : (p.isDark
                  ? AppColors.success.withValues(alpha: 0.14)
                  : AppColors.successTint);
        final calloutInk = isDeactivate
            ? (p.isDark ? const Color(0xFFFCA5A5) : AppColors.errorText)
            : (p.isDark ? const Color(0xFF86EFAC) : AppColors.successText);
        final actionFill = isDeactivate ? AppColors.error : AppColors.success;

        return AppDialog(
          icon: isDeactivate
              ? Icons.person_off_outlined
              : Icons.how_to_reg_outlined,
          title: '$verb ${user.fullName}?',
          subtitle: '${user.username} · ${user.email}',
          width: 460,
          content: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: calloutBg,
              borderRadius: BorderRadius.circular(AppRadii.medium),
              border: Border.all(color: actionFill.withValues(alpha: 0.28)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isDeactivate
                      ? Icons.info_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 18,
                  color: calloutInk,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isDeactivate
                        ? '${user.username} signs out on their next refresh. '
                              'Their history stays; the account is never deleted.'
                        : '${user.username} can sign in again.',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: calloutInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await viewmodel.setActive(user, isActive: !user.isActive);
              },
              style: TextButton.styleFrom(
                backgroundColor: actionFill,
                foregroundColor: AppColors.brandWhite,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(verb),
            ),
          ],
        );
      },
    );
  }

  /// Role change. Offers role CODES (what `assign_role` takes, and what the
  /// wire carries); the current roles preselect, minus any the viewer may not
  /// grant. Every offered role is one the server would accept from this viewer:
  /// a manager is never shown `admin`.
  Future<void> _openRoleDialog(
    BuildContext context,
    AdminUsersViewmodel viewmodel,
    User user, {
    required bool isAdmin,
    User? currentUser,
  }) async {
    if (AdminUserTable.isOwnAdminAccount(
      user: user,
      currentUserId: currentUser?.id,
      currentUsername: currentUser?.username,
    )) {
      return;
    }
    final roles = AdminUsersViewmodel.assignableRoles(isAdmin: isAdmin);
    return showDialog<void>(
      context: context,
      builder: (_) => _ChangeRoleDialog(
        viewmodel: viewmodel,
        user: user,
        roles: roles,
        isAdminViewer: isAdmin,
        currentUserId: currentUser?.id,
        currentUsername: currentUser?.username,
      ),
    );
  }
}

/// The multi-select role picker both dialogs share.
///
/// Keyed by CODE and labelled by the server's word for it, so the chip a person
/// taps and the code on the wire cannot drift apart.
class _RoleChips extends StatelessWidget {
  const _RoleChips({
    required this.roles,
    required this.selected,
    required this.onChanged,
  });

  final Map<String, String> roles;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final entry in roles.entries)
          FilterChip(
            label: Text(entry.value),
            selected: selected.contains(entry.key),
            // Keep explicit palette ink/fill so light and dark selected pills
            // always stay >= 4.5:1 WCAG AA contrast.
            backgroundColor: p.cardBackground,
            selectedColor: p.selected,
            checkmarkColor: p.accentInk,
            side: BorderSide(
              color: selected.contains(entry.key) ? p.accent : p.border,
            ),
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected.contains(entry.key) ? p.accentInk : p.textPrimary,
            ),
            onSelected: (on) {
              final next = {...selected};
              if (on) {
                next.add(entry.key);
              } else {
                next.remove(entry.key);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

/// Role picker. Sends the whole CODE list (`roles[]` is a full replacement);
/// the admin code is never offered to a non-admin caller (the server would 403
/// it anyway, and a manager must not grant it through a mixed list).
class _ChangeRoleDialog extends StatefulWidget {
  const _ChangeRoleDialog({
    required this.viewmodel,
    required this.user,
    required this.roles,
    required this.isAdminViewer,
    this.currentUserId,
    this.currentUsername,
  });

  final AdminUsersViewmodel viewmodel;
  final User user;
  final Map<String, String> roles;
  final bool isAdminViewer;
  final int? currentUserId;
  final String? currentUsername;

  @override
  State<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends State<_ChangeRoleDialog> {
  late Set<String> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Current roles preselect, limited to what this viewer may grant. An empty
    // result (a role-less account, or roles the viewer may not assign) starts
    // with nothing chosen rather than guessing on the person's behalf.
    _selected = {
      for (final code in widget.user.areaCodes)
        if (widget.roles.containsKey(code)) code,
    };
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final canSave = _selected.isNotEmpty && !_saving;
    final saveBg = p.isDark ? p.accent : AppColors.brandBlack;
    final saveFg = p.isDark ? p.onAccent : AppColors.brandWhite;

    return AppDialog(
      icon: Icons.manage_accounts_outlined,
      title: 'Change roles for ${widget.user.fullName}?',
      subtitle: '${widget.user.username} · ${widget.user.email}',
      width: 480,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Roles replace what the account has now. A role left out is '
            'removed.',
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const DialogSectionLabel('Main role'),
          _RoleChips(
            roles: widget.roles,
            selected: _selected,
            onChanged: (next) => setState(() => _selected = next),
          ),
          if (_selected.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Choose at least one role.',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: p.isDark ? const Color(0xFFFCA5A5) : AppColors.errorText,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const DialogSectionLabel('Permissions'),
          _RolePermissionsPreview(roleCodes: _selected),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: !canSave
              ? null
              : () async {
                  setState(() => _saving = true);
                  final ok = await widget.viewmodel.assignRoles(
                    widget.user,
                    roleCodes: _selected.toList(),
                    isAdminViewer: widget.isAdminViewer,
                    currentUserId: widget.currentUserId,
                    currentUsername: widget.currentUsername,
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          widget.viewmodel.actionError ??
                              'The roles could not be changed.',
                        ),
                      ),
                    );
                  }
                },
          style: TextButton.styleFrom(
            backgroundColor: canSave ? saveBg : p.surfaceSunken,
            foregroundColor: canSave ? saveFg : p.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.medium),
            ),
            textStyle: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Save roles'),
        ),
      ],
    );
  }
}

/// Account creation. At least one role is mandatory: the register endpoint
/// rejects an account with no role, and the payload carries `roles[]` only.
/// (An account can still LOSE its roles later — the list shows those as
/// "No role"; see [User.noRoleLabel].)
///
/// On a window of 700 px or more the four fields sit in two columns, so the
/// dialog is one screenful tall instead of two.
class _CreateAccountDialog extends StatefulWidget {
  const _CreateAccountDialog({
    required this.viewmodel,
    required this.isAdminViewer,
  });

  final AdminUsersViewmodel viewmodel;

  /// Admins may hand out Admin; nobody else is offered it.
  final bool isAdminViewer;

  @override
  State<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends State<_CreateAccountDialog> {
  final _username = TextEditingController();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _contactNumber = TextEditingController();
  Set<String> _roleCodes = const {'pos'};
  bool _obscurePassword = true;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _contactNumber.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _saving = true;
    });
    final ok = await widget.viewmodel.create(
      username: _username.text,
      email: _email.text,
      fullName: _fullName.text,
      password: _password.text,
      roleCodes: _roleCodes.toList(),
      isAdminViewer: widget.isAdminViewer,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Account created.')));
      }
      Navigator.of(context).pop();
    } else {
      setState(() => _error = widget.viewmodel.createError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    // Two columns only on a window wide enough to read them side by side; a
    // 760 px window gets the single stack, where each field is full width.
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final error = _error;

    final usernameField = TextField(
      controller: _username,
      decoration: const InputDecoration(
        labelText: 'Username',
        prefixIcon: Icon(Icons.person_outline_rounded, size: 18),
      ),
    );
    final fullNameField = TextField(
      controller: _fullName,
      decoration: const InputDecoration(
        labelText: 'Full name',
        prefixIcon: Icon(Icons.badge_outlined, size: 18),
      ),
    );
    final emailField = TextField(
      controller: _email,
      keyboardType: TextInputType.emailAddress,
      decoration: const InputDecoration(
        labelText: 'Email',
        prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
      ),
    );
    final passwordField = TextField(
      controller: _password,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Password',
        helperText: 'At least 8 characters',
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
        suffixIcon: IconButton(
          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
          onPressed: () =>
              setState(() => _obscurePassword = !_obscurePassword),
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 18,
          ),
        ),
      ),
    );
    final contactField = TextField(
      controller: _contactNumber,
      keyboardType: TextInputType.phone,
      decoration: const InputDecoration(
        labelText: 'Contact number',
        hintText: 'e.g. +63 912 345 6789',
        helperText: 'Optional',
        prefixIcon: Icon(Icons.phone_outlined, size: 18),
      ),
    );

    return AppDialog(
      icon: Icons.person_add_outlined,
      title: 'Create account',
      subtitle: 'Set up login credentials, main role, and module permissions.',
      width: wide ? 600 : 420,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.isDark
                    ? AppColors.error.withValues(alpha: 0.14)
                    : AppColors.errorTint,
                borderRadius: BorderRadius.circular(AppRadii.medium),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 17,
                    color: p.isDark
                        ? const Color(0xFFFCA5A5)
                        : AppColors.errorText,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: TextStyle(
                        fontSize: 13,
                        color: p.isDark
                            ? const Color(0xFFFCA5A5)
                            : AppColors.errorText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          const DialogSectionLabel('Account details'),
          if (wide) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: usernameField),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: fullNameField),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: emailField),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: passwordField),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            contactField,
          ] else
            _stack([
              usernameField,
              fullNameField,
              emailField,
              passwordField,
              contactField,
            ]),
          const SizedBox(height: AppSpacing.lg),
          const DialogSectionLabel('Main role'),
          Text(
            'Select the primary role for this account (you can combine roles '
            'if this staff member covers more than one area).',
            style: TextStyle(fontSize: 12.5, color: p.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          _RoleChips(
            roles: AdminUsersViewmodel.creatableRoles(),
            selected: _roleCodes,
            onChanged: (next) => setState(() => _roleCodes = next),
          ),
          const SizedBox(height: AppSpacing.lg),
          const DialogSectionLabel('Permissions'),
          _RolePermissionsPreview(roleCodes: _roleCodes),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  static Widget _stack(List<Widget> fields) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < fields.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpacing.md),
        fields[i],
      ],
    ],
  );
}

class _ModulePermission {
  const _ModulePermission({
    required this.module,
    required this.icon,
    required this.summary,
  });

  final String module;
  final IconData icon;
  final String summary;
}

/// Live preview of the modules unlocked by the selected main role(s).
class _RolePermissionsPreview extends StatelessWidget {
  const _RolePermissionsPreview({required this.roleCodes});

  final Set<String> roleCodes;

  static const Map<String, List<_ModulePermission>> _modulesByRole = {
    'pos': [
      _ModulePermission(
        module: 'POS & Till',
        icon: Icons.point_of_sale_outlined,
        summary: 'New transaction, history, held carts, shifts, returns, printer',
      ),
      _ModulePermission(
        module: 'Customer Release & Payments',
        icon: Icons.payments_outlined,
        summary: 'Release materials and record customer payments',
      ),
    ],
    'sales': [
      _ModulePermission(
        module: 'Sales & Quotations',
        icon: Icons.request_quote_outlined,
        summary: 'Transactions, quotations, sales orders, returns & reports',
      ),
      _ModulePermission(
        module: 'Projects & Receivables',
        icon: Icons.assignment_outlined,
        summary: 'Project requests review, receivables & cheque queue',
      ),
      _ModulePermission(
        module: 'Store Operations & Staff',
        icon: Icons.storefront_outlined,
        summary: 'Payables, deliveries, transfers & non-admin staff roles',
      ),
    ],
    'inventory': [
      _ModulePermission(
        module: 'Inventory & Stock Control',
        icon: Icons.inventory_2_outlined,
        summary: 'Products, categories, stock on hand, low stock & adjustments',
      ),
      _ModulePermission(
        module: 'Purchasing & Logistics',
        icon: Icons.local_shipping_outlined,
        summary: 'Suppliers, purchase orders, receiving, payables & transfers',
      ),
      _ModulePermission(
        module: 'Catalogue Files & Labels',
        icon: Icons.import_export_rounded,
        summary: 'Excel import/export, barcode lists & product labels',
      ),
    ],
    'bodega': [
      _ModulePermission(
        module: 'Bodega Operations',
        icon: Icons.qr_code_scanner_rounded,
        summary: 'Scan pick-ups, verify deliveries, read-only Bodega stock',
      ),
    ],
    'admin': [
      _ModulePermission(
        module: 'Shop Overview Dashboards',
        icon: Icons.dashboard_outlined,
        summary: 'Read-only System, Sales, Inventory, Bodega & Finance views',
      ),
      _ModulePermission(
        module: 'Governance & System',
        icon: Icons.admin_panel_settings_outlined,
        summary: 'User accounts, store settings, audit logs, backups & security',
      ),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final modules = <_ModulePermission>[
      for (final code in ['pos', 'sales', 'inventory', 'bodega', 'admin'])
        if (roleCodes.contains(code)) ...?_modulesByRole[code],
    ];

    if (modules.isEmpty) {
      return Container(
        key: const ValueKey('role-permissions-preview'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: p.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadii.medium),
          border: Border.all(color: p.border),
        ),
        child: Text(
          'Select a main role above to view its module permissions.',
          style: TextStyle(fontSize: 12.5, color: p.textSecondary),
        ),
      );
    }

    return Container(
      key: const ValueKey('role-permissions-preview'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < modules.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: p.border),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: p.selected,
                    borderRadius: BorderRadius.circular(AppRadii.small),
                  ),
                  child: Icon(
                    modules[i].icon,
                    size: 15,
                    color: p.accentInk,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        modules[i].module,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        modules[i].summary,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: p.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
