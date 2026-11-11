import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/user.dart';
import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:client/features/admin/widgets/admin_user_action_button.dart';
import 'package:client/features/admin/widgets/admin_user_table.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
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
          final isAdmin = context.read<AuthViewmodel>().roleName == 'admin';
          final content = _body(context, viewmodel, isAdmin: isAdmin);
          const subtitle = 'View and manage staff accounts.';
          if (widget.inSalesShell) {
            return SalesSkeletonLayout(
              title: 'Staff',
              subtitle: subtitle,
              // Staff is index 7 in the sales sidebar: Approvals (decision 01)
              // used to occupy 7 and is gone.
              selectedNavigationIndex: 7,
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
            selectedNavigationIndex: 1,
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
          Row(
            children: [
              // The summary line the four metric cards became. Absent until the
              // server has answered, so a failed first load never shows a zero.
              Expanded(
                child: stats == null
                    ? const SizedBox.shrink()
                    : Text(
                        _summary(stats),
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
              ),
              // FX5: beside the summary, so a reader who wonders where the other
              // accounts went has the way back in the same line as the count.
              if (filtersHideRows)
                TextButton(
                  onPressed: () => _clearFilters(viewmodel),
                  child: const Text('Clear filters'),
                ),
              // Creation stays Admin-only server-side (`register_view` is
              // `IsAdminRole`), so non-admins are not offered it.
              if (isAdmin)
                AdminUserActionButton(
                  label: 'Create account',
                  icon: Icons.person_add_outlined,
                  onPressed: () =>
                      _openCreateDialog(context, viewmodel, isAdmin: isAdmin),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (firstLoadFailed)
            ErrorBanner(message: viewmodel.loadError!, onRetry: viewmodel.load)
          else ...[
            FilterBar(
              searchController: _searchController,
              searchHint: 'Search name, username, or email',
              onSearchChanged: (value) => setState(() => _query = value),
              // Only the roles the loaded rows actually carry, plus "No role":
              // filtering to a group nobody has would be an empty promise.
              options: [_anyRole, ...viewmodel.availableRoles],
              selected: viewmodel.roleFilter ?? _anyRole,
              onSelected: (chip) =>
                  viewmodel.setRoleFilter(chip == _anyRole ? null : chip),
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
                emptyMessage: filtered
                    ? 'No accounts match these filters.'
                    : 'No staff accounts yet.',
                // Only a first read may take the slot: a refresh keeps its rows.
                isLoading: viewmodel.isLoading && !viewmodel.hasLoaded,
                onToggleActive: (user) =>
                    _openToggleDialog(context, viewmodel, user),
                onChangeRole: (user) =>
                    _openRoleDialog(context, viewmodel, user, isAdmin: isAdmin),
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
      builder: (dialogContext) => AlertDialog(
        title: Text('$verb ${user.fullName}?'),
        content: Text(
          user.isActive
              ? '${user.username} signs out on their next refresh. '
                    'Their history stays; the account is never deleted.'
              : '${user.username} can sign in again.',
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
            child: Text(verb),
          ),
        ],
      ),
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
  }) {
    final roles = AdminUsersViewmodel.assignableRoles(isAdmin: isAdmin);
    return showDialog<void>(
      context: context,
      builder: (_) => _ChangeRoleDialog(
        viewmodel: viewmodel,
        user: user,
        roles: roles,
        isAdminViewer: isAdmin,
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
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final entry in roles.entries)
          FilterChip(
            label: Text(entry.value),
            selected: selected.contains(entry.key),
            // The house FilterBar chip, in the same words `chipTheme` cannot
            // say: a Material chip paints its label with `labelStyle` whether
            // or not it is selected (Flutter 3.47), so the theme's black
            // `selectedColor` gave a black pill with a black-on-black label.
            // Gold tint, dark gold ink, and the fill/border the bar uses.
            backgroundColor: AppColors.cardBackground,
            selectedColor: AppColors.selected,
            checkmarkColor: AppColors.brandGoldText,
            side: BorderSide(
              color: selected.contains(entry.key)
                  ? AppColors.brandGold
                  : AppColors.border,
            ),
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected.contains(entry.key)
                  ? AppColors.brandGoldText
                  : AppColors.textPrimary,
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
  });

  final AdminUsersViewmodel viewmodel;
  final User user;
  final Map<String, String> roles;
  final bool isAdminViewer;

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
    final canSave = _selected.isNotEmpty && !_saving;
    return AlertDialog(
      title: Text('Change roles for ${widget.user.fullName}?'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Roles replace what the account has now. A role left out is '
              'removed.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            _RoleChips(
              roles: widget.roles,
              selected: _selected,
              onChanged: (next) => setState(() => _selected = next),
            ),
            if (_selected.isEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              const Text('Choose at least one role.'),
            ],
          ],
        ),
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
  final _email = TextEditingController();
  final _fullName = TextEditingController();
  final _password = TextEditingController();
  Set<String> _roleCodes = const {'pos'};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _fullName.dispose();
    _password.dispose();
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
    // Two columns only on a window wide enough to read them side by side; a
    // 760 px window gets the single stack, where each field is full width.
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final error = _error;
    final identity = <Widget>[
      TextField(
        controller: _username,
        decoration: const InputDecoration(labelText: 'Username'),
      ),
      TextField(
        controller: _email,
        decoration: const InputDecoration(labelText: 'Email'),
      ),
      TextField(
        controller: _fullName,
        decoration: const InputDecoration(labelText: 'Full name'),
      ),
      TextField(
        controller: _password,
        decoration: const InputDecoration(labelText: 'Password'),
        obscureText: true,
      ),
      // Multi-select: an account may hold several areas (Phase 4 F3b). The
      // chips are keyed by code, so the label on screen and the code on the
      // wire cannot drift apart.
      _RoleChips(
        roles: AdminUsersViewmodel.assignableRoles(
          isAdmin: widget.isAdminViewer,
        ),
        selected: _roleCodes,
        onChanged: (next) => setState(() => _roleCodes = next),
      ),
    ];

    return AlertDialog(
      title: const Text('Create account'),
      content: SizedBox(
        width: wide ? 520 : 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(error, style: const TextStyle(color: Colors.red)),
                ),
              // Two fields per column on a wide window, one stack on a narrow
              // one: same fields, same order, only the arrangement changes.
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _stack(identity.sublist(0, 3))),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: _stack(identity.sublist(3))),
                  ],
                )
              else
                _stack(identity),
            ],
          ),
        ),
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
        if (i > 0) const SizedBox(height: AppSpacing.sm),
        fields[i],
      ],
    ],
  );
}
