import 'package:client/core/constants/app_breakpoints.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:client/shared/widgets/system_brand.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The frame every signed-in screen sits in: sidebar, header, body.
///
/// It follows the window width (see [AppBreakpoints]): a full sidebar on a
/// wide window, an icon rail when the window is resized narrower, and a
/// drawer behind a menu button when it is about half a screen or less. The
/// role shells (POS, inventory, sales, admin) only supply their menu.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.sections,
    required this.selectedIndex,
    required this.child,
    this.onDestinationSelected,
    this.actions = const [],
    this.fallbackUserName = '[ USER NAME ]',
    this.fallbackRoleLabel = '[ ROLE ]',
    this.scrollable = true,
  });

  final String title;
  final String subtitle;
  final List<SharedSidebarSection> sections;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final List<Widget> actions;
  final String fallbackUserName;
  final String fallbackRoleLabel;
  final Widget child;

  /// When false the body gets the exact height left under the header instead
  /// of a scroll view, for screens that lay out their own scrolling regions
  /// (the till keeps its Pay button on screen this way).
  final bool scrollable;

  static const double headerHeight = 72;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mode = shellModeFor(constraints.maxWidth);
        final compact = mode == ShellMode.compact;
        final padding = compact ? AppSpacing.lg : AppSpacing.xl;

        final body = scrollable
            ? SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: child,
              )
            : Padding(padding: EdgeInsets.all(padding), child: child);

        return Scaffold(
          backgroundColor: AppColors.background,
          drawer: compact
              ? Drawer(
                  width: SharedSidebar.width,
                  shape: const RoundedRectangleBorder(),
                  child: _SidebarPanel(
                    shell: this,
                    collapsed: false,
                    closeDrawerOnSelect: true,
                  ),
                )
              : null,
          body: Row(
            children: [
              if (!compact)
                Container(
                  width: mode == ShellMode.rail
                      ? SharedSidebar.railWidth
                      : SharedSidebar.width,
                  decoration: const BoxDecoration(
                    color: AppColors.cardBackground,
                    border: Border(right: BorderSide(color: AppColors.border)),
                  ),
                  child: _SidebarPanel(
                    shell: this,
                    collapsed: mode == ShellMode.rail,
                    closeDrawerOnSelect: false,
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    _Header(shell: this, showMenuButton: compact),
                    Expanded(child: body),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SidebarPanel extends StatelessWidget {
  const _SidebarPanel({
    required this.shell,
    required this.collapsed,
    required this.closeDrawerOnSelect,
  });

  final AppShell shell;
  final bool collapsed;
  final bool closeDrawerOnSelect;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewmodel>();
    final name = auth.user?.fullName ?? shell.fallbackUserName;
    final role = auth.user?.roleLabel ?? shell.fallbackRoleLabel;
    final onSelected = shell.onDestinationSelected;

    return Material(
      color: AppColors.cardBackground,
      child: Column(
        children: [
          SizedBox(
            height: AppShell.headerHeight,
            child: Center(
              child: collapsed
                  ? const SystemBrand(logoSize: 40, showName: false)
                  : const SystemBrand(
                      logoSize: 42,
                      fontSize: 14,
                      subtitle: '& CONSTRUCTION SUPPLIES',
                    ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SharedSidebar(
              sections: shell.sections,
              selectedIndex: shell.selectedIndex,
              collapsed: collapsed,
              onDestinationSelected: onSelected == null
                  ? null
                  : (index) {
                      if (closeDrawerOnSelect) Navigator.of(context).pop();
                      onSelected(index);
                    },
            ),
          ),
          const Divider(height: 1),
          if (collapsed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                children: [
                  Tooltip(
                    message: '$name · $role',
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.brandBlack,
                      foregroundColor: AppColors.brandGoldLight,
                      child: Text(
                        _initials(name),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Log out',
                    onPressed: auth.logout,
                    icon: const Icon(Icons.logout, size: 18),
                  ),
                ],
              ),
            )
          else
            ListTile(
              title: Text(name, overflow: TextOverflow.ellipsis),
              subtitle: Text(role, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Log out',
                onPressed: auth.logout,
                icon: const Icon(Icons.logout, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty && part[0] != '[')
        .toList();
    if (parts.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.shell, required this.showMenuButton});

  final AppShell shell;
  final bool showMenuButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: AppShell.headerHeight,
      padding: EdgeInsets.symmetric(
        horizontal: showMenuButton ? AppSpacing.sm : AppSpacing.xl,
      ),
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (showMenuButton) ...[
            IconButton(
              tooltip: 'Open menu',
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shell.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  shell.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ...shell.actions,
        ],
      ),
    );
  }
}
