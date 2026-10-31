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
              selectedNavigationIndex: 8,
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

    return Column(
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
            // Creation stays Admin-only server-side (`register_view` is
            // `IsAdminRole`), so non-admins are not offered it.
            if (isAdmin)
              AdminUserActionButton(
                label: 'Create account',
                icon: Icons.person_add_outlined,
                onPressed: () => _openCreateDialog(context, viewmodel),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (firstLoadFailed)
          ErrorBanner(message: viewmodel.loadError!, onRetry: viewmodel.load)
        else ...[
          FilterBar(
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
            onExtraSelected: (chip) => viewmodel.setActiveFilter(switch (chip) {
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
            ErrorBanner(message: viewmodel.loadError!, onRetry: viewmodel.load),
            const SizedBox(height: AppSpacing.md),
          ],
          Expanded(
            child: AdminUserTable(
              users: rows,
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
    );
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
    AdminUsersViewmodel viewmodel,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => _CreateAccountDialog(viewmodel: viewmodel),
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

  /// Role change. Offers GROUP names (what `assign_role` takes); the current
  /// group preselects only when it is itself assignable.
  Future<void> _openRoleDialog(
    BuildContext context,
    AdminUsersViewmodel viewmodel,
    User user, {
    required bool isAdmin,
  }) {
    final groups = AdminUsersViewmodel.assignableGroups(isAdmin: isAdmin);
    return showDialog<void>(
      context: context,
      builder: (_) =>
          _ChangeRoleDialog(viewmodel: viewmodel, user: user, groups: groups),
    );
  }
}

/// Role picker. Sends the GROUP name; the list never contains admin groups
/// for non-admin callers (the server would 403 them anyway).
class _ChangeRoleDialog extends StatefulWidget {
  const _ChangeRoleDialog({
    required this.viewmodel,
    required this.user,
    required this.groups,
  });

  final AdminUsersViewmodel viewmodel;
  final User user;
  final List<String> groups;

  @override
  State<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends State<_ChangeRoleDialog> {
  late String _group;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _group = widget.groups.contains(widget.user.roleLabel)
        ? widget.user.roleLabel
        : widget.groups.first;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Change role for ${widget.user.fullName}?'),
      content: DropdownButtonFormField<String>(
        initialValue: _group,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Group'),
        items: [
          for (final group in widget.groups)
            DropdownMenuItem(
              value: group,
              child: Text(group, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _group = value);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  final ok = await widget.viewmodel.assignRole(
                    widget.user,
                    groupName: _group,
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  if (!ok) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          widget.viewmodel.actionError ??
                              'The role could not be changed.',
                        ),
                      ),
                    );
                  }
                },
          child: const Text('Change role'),
        ),
      ],
    );
  }
}

/// Account creation. The group is mandatory: the register endpoint rejects a
/// groupless account. (An account can still LOSE its group later — the list
/// shows those as "No role"; see [User.noRoleLabel].)
///
/// On a window of 700 px or more the four fields sit in two columns, so the
/// dialog is one screenful tall instead of two.
class _CreateAccountDialog extends StatefulWidget {
  const _CreateAccountDialog({required this.viewmodel});

  final AdminUsersViewmodel viewmodel;

  @override
  State<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends State<_CreateAccountDialog> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _fullName = TextEditingController();
  final _password = TextEditingController();
  String _group = 'Cashier';
  String? _error;
  bool _saving = false;

  static const _groups = ['Admin', 'Stock Manager', 'Cashier', 'Store Manager'];

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
      groupName: _group,
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
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _group,
        decoration: const InputDecoration(labelText: 'Role'),
        items: [
          for (final group in _groups)
            DropdownMenuItem(value: group, child: Text(group)),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _group = value);
        },
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
