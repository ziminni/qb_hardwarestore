import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:client/features/admin/widgets/admin_user_action_button.dart';
import 'package:client/features/admin/widgets/admin_user_filters.dart';
import 'package:client/features/admin/widgets/admin_user_metric_card.dart';
import 'package:client/features/admin/widgets/admin_user_section.dart';
import 'package:client/features/admin/widgets/admin_user_table.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The admin User Management screen.
///
/// Lists staff accounts with server-computed totals, searches server-side,
/// filters role/status client-side, and creates accounts through the register
/// shape (which mandates a group). Row view/edit actions do not exist yet —
/// the per-row buttons that opened nothing are gone rather than kept as
/// decoration; account edits are a specified future, not a silent no-op.
class AdminUserManagementPage extends StatefulWidget {
  const AdminUserManagementPage({super.key, this.viewmodel});

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
          return AdminSkeletonLayout(
            title: 'User Management',
            subtitle: 'View and manage staff accounts.',
            selectedNavigationIndex: 1,
            child: Column(
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
                  AdminUserSection(
                    title: 'User accounts',
                    child: viewmodel.users.isEmpty
                        ? const Text('No staff accounts found.')
                        : AdminUserTable(users: viewmodel.users),
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
            ),
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
/// groupless account, and the client `User` requires a non-null role.
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created.')),
        );
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
