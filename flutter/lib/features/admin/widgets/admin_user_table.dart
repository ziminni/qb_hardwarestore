import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/theme/app_palette.dart';
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
    this.currentUserId,
    this.currentUsername,
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

  /// Signed-in user's ID and username so an Admin cannot modify roles on their
  /// own Admin account.
  final int? currentUserId;
  final String? currentUsername;

  /// An account the server counts as admin: one 'admin' role CODE, which
  /// `serializers.py` sends for both the Admin and System Administrator groups.
  /// Compare the CODE, never the display label (Phase 4 lesson), and check
  /// EVERY assigned role: an account holding Admin beside Cashier is admin-bound
  /// too, so a manager must not be offered a write on it.
  static bool _isAdminAccount(User user) =>
      user.assignedRoles.any((role) => role.code == 'admin');

  /// True when [user] is the currently signed-in Admin's own Admin account.
  static bool isOwnAdminAccount({
    required User user,
    int? currentUserId,
    String? currentUsername,
  }) {
    if (!_isAdminAccount(user)) return false;
    if (currentUserId != null && user.id == currentUserId) return true;
    if (currentUsername != null &&
        currentUsername.isNotEmpty &&
        user.username == currentUsername) {
      return true;
    }
    return false;
  }

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
          cell: (user) => _AccountCell(user: user),
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
                  canChangeRole: !isOwnAdminAccount(
                    user: user,
                    currentUserId: currentUserId,
                    currentUsername: currentUsername,
                  ),
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
}

/// Full name over `username · email` with a role-tinted initials avatar and
/// status indicator dot.
class _AccountCell extends StatelessWidget {
  const _AccountCell({required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Row(
      children: [
        _Initials(
          name: user.fullName,
          isActive: user.isActive,
          tone: _roleTone(user),
        ),
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
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${user.username} · ${user.email}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p.textSecondary),
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
    this.canChangeRole = true,
  });

  final User user;
  final VoidCallback onToggleActive;
  final VoidCallback onChangeRole;
  final bool canChangeRole;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final isDeactivate = user.isActive;
    final toggleBg = isDeactivate
        ? (p.isDark
              ? AppColors.error.withValues(alpha: 0.16)
              : AppColors.errorTint)
        : (p.isDark
              ? AppColors.success.withValues(alpha: 0.16)
              : AppColors.successTint);
    final toggleFg = isDeactivate
        ? (p.isDark ? const Color(0xFFFCA5A5) : AppColors.errorText)
        : (p.isDark ? const Color(0xFF86EFAC) : AppColors.successText);
    final toggleBorder = isDeactivate
        ? AppColors.error.withValues(alpha: p.isDark ? 0.32 : 0.22)
        : AppColors.success.withValues(alpha: p.isDark ? 0.32 : 0.22);

    // A Wrap, not a Row: on a card the two buttons get a column width, and a
    // Row would paint them past the edge with an overflow stripe.
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: 6,
      children: [
        if (canChangeRole)
          TextButton.icon(
            onPressed: onChangeRole,
            style: TextButton.styleFrom(
              backgroundColor: p.surfaceSunken,
              foregroundColor: p.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              minimumSize: const Size(44, 38),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.small),
                side: BorderSide(color: p.border),
              ),
              textStyle: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            icon: Icon(
              Icons.manage_accounts_outlined,
              size: 15,
              color: p.accentInk,
            ),
            label: const Text('Change role'),
          ),
        TextButton.icon(
          onPressed: onToggleActive,
          style: TextButton.styleFrom(
            backgroundColor: toggleBg,
            foregroundColor: toggleFg,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            minimumSize: const Size(44, 38),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.small),
              side: BorderSide(color: toggleBorder),
            ),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: Icon(
            isDeactivate
                ? Icons.person_off_outlined
                : Icons.person_outline_rounded,
            size: 15,
          ),
          label: Text(isDeactivate ? 'Deactivate' : 'Reactivate'),
        ),
      ],
    );
  }
}

/// The account's initials in a role-tinted circular badge with a live status
/// indicator dot: staff read people, not ids.
class _Initials extends StatelessWidget {
  const _Initials({
    required this.name,
    required this.isActive,
    required this.tone,
  });

  final String name;
  final bool isActive;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final (Color bg, Color fg, Color ring) = switch (tone) {
      StatusTone.info => (
        p.selected,
        p.accentInk,
        p.accent.withValues(alpha: 0.48),
      ),
      StatusTone.success => (
        p.isDark ? const Color(0xFF14291E) : AppColors.successTint,
        p.isDark ? const Color(0xFF86EFAC) : AppColors.successText,
        AppColors.success.withValues(alpha: 0.35),
      ),
      StatusTone.warning => (
        p.isDark ? const Color(0xFF2B2110) : AppColors.warningTint,
        p.isDark ? const Color(0xFFFCD34D) : AppColors.warningText,
        AppColors.warning.withValues(alpha: 0.4),
      ),
      _ => (p.surfaceSunken, p.textPrimary, p.border),
    };

    final avatar = Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: ring),
      ),
      child: Text(
        _initials(name),
        style: TextStyle(
          fontFamily: AppTextStyles.cinzelFont,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(opacity: isActive ? 1.0 : 0.58, child: avatar),
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: isActive ? AppColors.success : p.textSecondary,
              shape: BoxShape.circle,
              border: Border.all(color: p.cardBackground, width: 2),
            ),
          ),
        ),
      ],
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
