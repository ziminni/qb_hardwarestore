import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/user.dart';
import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/admin/widgets/admin_user_action_button.dart';
import 'package:client/features/admin/widgets/admin_user_filters.dart';
import 'package:client/features/admin/widgets/admin_user_metric_card.dart';
import 'package:client/features/admin/widgets/admin_user_section.dart';
import 'package:client/features/admin/widgets/admin_user_table.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The admin User Management screen.
///
/// Lists staff accounts with server-computed totals, searches server-side,
/// filters role/status client-side, creates accounts through the register
/// shape (admins only — creation stays Admin-only server-side), and offers
/// deactivate/reactivate + role change per row (Phase 5: Store Managers act
/// on non-admin staff; the server refuses admin-bound changes with 403
/// `USER_ADMIN_FORBIDDEN` and the last-admin strip with 400 `LAST_ADMIN`).
/// Role identity is compared by GROUP name (what `assign_role` takes), never
/// by display label or client role code.
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
          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Staff accounts',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // Creation stays Admin-only server-side (`register_view`
                  // is `IsAdminRole`), so non-admins are not offered it.
                  if (isAdmin)
                    AdminUserActionButton(
                      label: 'Create account',
                      icon: Icons.person_add_outlined,
                      onPressed: () => _openCreateDialog(context, viewmodel),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (viewmodel.isLoading && !viewmodel.hasLoaded)
                const Center(child: CircularProgressIndicator())
              else if (!viewmodel.hasLoaded && viewmodel.loadError != null)
                LiveLoadErrorBanner(
                  message: viewmodel.loadError!,
                  onRetry: viewmodel.load,
                )
              else ...[
                _Metrics(viewmodel: viewmodel),
                const SizedBox(height: 16),
                AdminUserSection(
                  title: 'Search and filters',
                  child: AdminUserFilters(
                    initialQuery: viewmodel.searchQuery,
                    availableRoles: viewmodel.availableRoles,
                    roleFilter: viewmodel.roleFilter,
                    activeFilter: viewmodel.activeFilter,
                    onSearch: (query) => viewmodel.load(search: query),
                    onRoleChanged: viewmodel.setRoleFilter,
                    onActiveChanged: viewmodel.setActiveFilter,
                    onClear: viewmodel.clearFilters,
                  ),
                ),
                const SizedBox(height: 16),
                if (viewmodel.actionError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: LiveLoadErrorBanner(
                      message: viewmodel.actionError!,
                      onRetry: viewmodel.clearActionError,
                    ),
                  ),
                AdminUserSection(
                  title: 'User accounts',
                  child: viewmodel.users.isEmpty
                      ? const Text('No staff accounts found.')
                      : AdminUserTable(
                          users: viewmodel.users,
                          onToggleActive: (user) =>
                              _openToggleDialog(context, viewmodel, user),
                          onChangeRole: (user) => _openRoleDialog(
                            context,
                            viewmodel,
                            user,
                            isAdmin: isAdmin,
                          ),
                        ),
                ),
              ],
              if (viewmodel.hasLoaded && viewmodel.loadError != null) ...[
                const SizedBox(height: 16),
                LiveLoadErrorBanner(
                  message: viewmodel.loadError!,
                  onRetry: viewmodel.load,
                ),
              ],
            ],
          );
          const subtitle = 'View and manage staff accounts.';
          if (widget.inSalesShell) {
            return SalesSkeletonLayout(
              title: 'Staff',
              subtitle: subtitle,
              selectedNavigationIndex: 8,
              onNavigationSelected: (index) => navigateSales(context, index),
              child: content,
            );
          }
          return AdminSkeletonLayout(
            title: 'User Management',
            subtitle: subtitle,
            selectedNavigationIndex: 1,
            child: content,
          );
        },
      ),
    );
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

class _Metrics extends StatelessWidget {
  const _Metrics({required this.viewmodel});

  final AdminUsersViewmodel viewmodel;

  @override
  Widget build(BuildContext context) {
    final stats = viewmodel.stats;
    if (stats == null) return const SizedBox.shrink();
    final cards = [
      ('Total accounts', '${stats.total}'),
      ('Active accounts', '${stats.active}'),
      ('Inactive accounts', '${stats.inactive}'),
      ('Roles assigned', '${stats.rolesAssigned}'),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final card in cards)
          SizedBox(
            width: 190,
            child: AdminUserMetricCard(label: card.$1, value: card.$2),
          ),
      ],
    );
  }
}

/// Account creation. The group is mandatory: the register endpoint rejects a
/// groupless account. (An account can still LOSE its group later — the list
/// shows those as "No role"; see [User.noRoleLabel].)
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
    return AlertDialog(
      title: const Text('Create account'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
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
          ],
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
}
