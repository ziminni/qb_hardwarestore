import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/user.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// The staff account list: a table on a wide window, one card per account on a
/// narrow one, both from [DataPanel].
///
/// The row actions live INSIDE the row. The previous `DataTable` put them in a
/// last column that a 760 px window scrolled off the side, so a Store Manager on
/// a small screen could not deactivate anyone; a card now carries the same two
/// buttons under the account's details.
///
/// Every word about authority comes from the caller: this widget only reports
/// which account was tapped. Nothing is written here, and no row is edited
/// locally: the page reloads and shows what the server owns.
class AdminUserTable extends StatelessWidget {
  const AdminUserTable({
    super.key,
    required this.users,
    required this.emptyMessage,
    required this.onToggleActive,
    required this.onChangeRole,
    required this.isAdminViewer,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.controller,
  });

  final List<User> users;

  /// Worded by the page: "nothing matches these filters" and "no accounts yet"
  /// are different facts.
  final String emptyMessage;

  /// True only for a first read with nothing on screen yet: a refresh must not
  /// replace the rows with a spinner.
  final bool isLoading;

  /// A failed read. The page normally shows this in its own banner above the
  /// rows it kept, and passes null here.
  final String? error;
  final VoidCallback? onRetry;

  /// Opens the deactivate/reactivate confirm for this account.
  final ValueChanged<User> onToggleActive;

  /// Opens the role picker for this account.
  final ValueChanged<User> onChangeRole;

  /// The rows' own scroll position, so the page can hand it a wheel that landed
  /// on its header. See [DataPanel.controller].
  final ScrollController? controller;

  /// Whether the person reading the list holds the admin role CODE ('admin').
  ///
  /// The server refuses a non-admin's change to an admin account with 403
  /// `USER_ADMIN_FORBIDDEN`, so a Store Manager is offered no row actions on
  /// those rows instead of a button that can only fail.
  final bool isAdminViewer;

  /// An account the server counts as admin: one 'admin' role CODE, which
  /// `serializers.py` sends for both the Admin and System Administrator groups.
  /// Compare the CODE, never the display label (Phase 4 lesson), and check
  /// EVERY assigned role: an account holding Admin beside Cashier is admin-bound
  /// too, so a manager must not be offered a write on it.
  static bool _isAdminAccount(User user) =>
      user.assignedRoles.any((role) => role.code == 'admin');

  /// Only an admin may act on an admin account. Phase 5 rules the server owns
  /// still apply on top (LAST_ADMIN, self-approval); this only stops the client
  /// from offering a write the server will refuse.
  static bool mayActOn({required bool isAdminViewer, required User user}) =>
      isAdminViewer || !_isAdminAccount(user);

  @override
  Widget build(BuildContext context) {
    return DataPanel<User>(
      title: 'Staff accounts',
      count: users.length,
      columns: [
        DataPanelColumn<User>(
          label: 'Account',
          // The primary text column: a long full name must have room to read
          // instead of ellipsizing beside a two-word badge.
          flex: 3,
          cell: _accountCell,
        ),
        DataPanelColumn<User>(
          label: 'Role',
          flex: 2,
          cell: (user) =>
              StatusBadge(label: user.roleLabel, tone: _roleTone(user)),
        ),
        DataPanelColumn<User>(
          label: 'Status',
          flex: 2,
          cell: (user) => StatusBadge(
            label: user.isActive ? 'Active' : 'Inactive',
            tone: user.isActive ? StatusTone.success : StatusTone.neutral,
          ),
        ),
        DataPanelColumn<User>(
          label: 'Actions',
          flex: 3,
          cell: (user) => mayActOn(isAdminViewer: isAdminViewer, user: user)
              ? _Actions(
                  user: user,
                  onToggleActive: () => onToggleActive(user),
                  onChangeRole: () => onChangeRole(user),
                )
              : const SizedBox.shrink(),
        ),
      ],
      rows: users,
      controller: controller,
      emptyMessage: emptyMessage,
      isLoading: isLoading,
      error: error,
      onRetry: onRetry,
      // Stable per account, so a filtered list never reuses another row's state.
      rowKey: (user) => ValueKey('admin.user.${user.id}'),
    );
  }

  /// Full name over `username · email`.
  ///
  /// The three were three columns before, which cost the width the account name
  /// and the actions needed. Together they are one fact: who this is.
  static Widget _accountCell(User user) {
    return Row(
      children: [
        _Initials(user.fullName),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${user.username} · ${user.email}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One tone per kind of role, so the tier is readable without reading it.
///
/// The five tones cannot give every group its own color, so the two tiers that
/// decide what an account may do (admin, store/stock manager) are colored and
/// the working groups share the neutral pill. A groupless account keeps the
/// warning tone: it is the one state somebody has to fix.
StatusTone _roleTone(User user) {
  if (user.assignedRoles.isEmpty) return StatusTone.warning;
  // Widest first is how `roles[]` arrives, so the first code decides the tone.
  return switch (user.assignedRoles.first.code) {
    'admin' => StatusTone.info,
    'sales' || 'inventory' => StatusTone.success,
    _ => StatusTone.neutral,
  };
}

/// Deactivate/Reactivate plus Change role, wrapped so a narrow card stacks them
/// instead of overflowing the row.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.user,
    required this.onToggleActive,
    required this.onChangeRole,
  });

  final User user;
  final VoidCallback onToggleActive;
  final VoidCallback onChangeRole;

  @override
  Widget build(BuildContext context) {
    // A Wrap, not a Row: on a card the two buttons get a column width, and a
    // Row would paint them past the edge with an overflow stripe.
    return Wrap(
      spacing: AppSpacing.sm,
      children: [
        TextButton(
          onPressed: onToggleActive,
          style: _compact,
          child: Text(user.isActive ? 'Deactivate' : 'Reactivate'),
        ),
        TextButton(
          onPressed: onChangeRole,
          style: _compact,
          child: const Text('Change role'),
        ),
      ],
    );
  }

  /// Keeps both actions on one line at 1100 px: the default 16 px side padding
  /// alone costs more than the row has to spare.
  static final ButtonStyle _compact = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    minimumSize: const Size(44, 44),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

/// The account's initials in a gold-tinted circle: staff read people, not ids.
class _Initials extends StatelessWidget {
  const _Initials(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.selected,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials(name),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  /// First letter of the first two words. A nameless account shows "?" rather
  /// than an empty circle.
  static String _initials(String name) {
    final words = name.trim().split(RegExp(r'\s+'));
    final letters = [
      for (final word in words)
        if (word.isNotEmpty) word[0].toUpperCase(),
    ];
    if (letters.isEmpty) return '?';
    return letters.take(2).join();
  }
}
