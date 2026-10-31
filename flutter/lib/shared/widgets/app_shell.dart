import 'package:client/core/constants/app_breakpoints.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:client/shared/widgets/measure_ruler.dart';
import 'package:client/shared/widgets/system_brand.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The frame every signed-in screen sits in: sidebar, header, body.
///
/// It follows the window width (see [AppBreakpoints]): a full sidebar on a
/// wide window, an icon rail when the window is resized narrower, and a
/// drawer behind a menu button when it is about half a screen or less. The
/// role shells (POS, inventory, sales, admin) only supply their menu.
class AppShell extends StatefulWidget {
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
    this.loadMarkers,
    this.markers,
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

  /// Live counts for the sidebar, keyed by the flat destination index (the
  /// same number [selectedIndex] uses). Read once when the shell mounts; a
  /// failed read leaves every destination blank.
  final Future<Map<int, int>> Function()? loadMarkers;

  /// Counts the caller already holds, keyed like [loadMarkers], for a page whose
  /// own data IS the count (Low stock's open alerts). Read on EVERY build and
  /// used instead of [loadMarkers], so resolving the last alert clears the
  /// badge on the same screen instead of on the next visit. A zero is drawn as
  /// nothing, and a caller with nothing confirmed passes nothing.
  final Map<int, int>? markers;

  /// When false the body gets the exact height left under the header instead
  /// of a scroll view, for screens that lay out their own scrolling regions
  /// (the till keeps its Pay button on screen this way).
  final bool scrollable;

  static const double headerHeight = 72;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Map<int, int> _loadedMarkers = const {};

  /// [AppShell.markers] when the caller has its own counts, else whatever the
  /// one-off read answered. Both are filtered to positive counts by their
  /// producers or by [SharedSidebar].
  Map<int, int> get _markers => widget.markers ?? _loadedMarkers;

  /// The user's choice from the collapse button. Only consulted on a window
  /// wide enough to show the full sidebar ([AppBreakpoints.expanded]); a
  /// narrow window and the drawer ignore it.
  bool _collapsedByUser = false;

  @override
  void initState() {
    super.initState();
    _restoreCollapse();
    // A caller that supplies its own counts owns them; a second read here would
    // be a duplicate request whose answer the caller cannot see.
    if (widget.markers == null) _loadMarkers();
  }

  Future<void> _restoreCollapse() async {
    final stored = await SidebarCollapsePreference.read();
    if (!mounted || stored == _collapsedByUser) return;
    setState(() => _collapsedByUser = stored);
  }

  Future<void> _loadMarkers() async {
    final load = widget.loadMarkers;
    if (load == null) return;
    final Map<int, int> counts;
    try {
      counts = await load();
    } catch (_) {
      // A sidebar marker is a convenience, never the page's own data: a failed
      // read shows nothing and the page behind it reports its own errors.
      return;
    }
    if (!mounted) return;
    // A later read replaces the whole map, so a count that dropped to zero
    // clears its badge instead of leaving the mount-time number on screen.
    setState(() => _loadedMarkers = _positiveMarkers(counts));
  }

  static Map<int, int> _positiveMarkers(Map<int, int> counts) => {
    for (final entry in counts.entries)
      if (entry.value > 0) entry.key: entry.value,
  };

  Future<void> _toggleCollapsed() async {
    setState(() => _collapsedByUser = !_collapsedByUser);
    await SidebarCollapsePreference.write(_collapsedByUser);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mode = shellModeFor(constraints.maxWidth);
        final compact = mode == ShellMode.compact;
        final padding = compact ? AppSpacing.lg : AppSpacing.xl;
        // The stored choice only ever turns the wide sidebar into the rail; it
        // cannot widen a window that is too narrow for labels.
        final rail =
            mode == ShellMode.rail ||
            (mode == ShellMode.expanded && _collapsedByUser);

        final body = widget.scrollable
            ? SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: widget.child,
              )
            : Padding(padding: EdgeInsets.all(padding), child: widget.child);

        return Scaffold(
          backgroundColor: AppColors.background,
          drawer: compact
              ? Drawer(
                  width: SharedSidebar.width,
                  backgroundColor: AppColors.chrome,
                  shape: const RoundedRectangleBorder(),
                  child: _SidebarPanel(
                    shell: widget,
                    markers: _markers,
                    collapsed: false,
                    closeDrawerOnSelect: true,
                  ),
                )
              : null,
          body: Row(
            children: [
              if (!compact)
                Container(
                  width: rail ? SharedSidebar.railWidth : SharedSidebar.width,
                  decoration: const BoxDecoration(
                    // The dark chrome: one black surface behind the whole nav
                    // column, with a hairline against the cream page body.
                    color: AppColors.chrome,
                    border: Border(
                      right: BorderSide(color: AppColors.chromeBorder),
                    ),
                  ),
                  child: _SidebarPanel(
                    shell: widget,
                    markers: _markers,
                    collapsed: rail,
                    closeDrawerOnSelect: false,
                    onToggleCollapsed: mode == ShellMode.expanded
                        ? _toggleCollapsed
                        : null,
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    _Header(shell: widget, showMenuButton: compact),
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

/// The collapse button's one stored value: whether the user chose the icon
/// rail on a wide window. Read on mount, written on toggle, restored on the
/// next build or app start.
///
/// Both halves swallow a failure on purpose: a missing or unreadable store
/// (a test binding, a platform without the plugin) must not stop the shell
/// from rendering, and the fallback is the wide window's own default.
class SidebarCollapsePreference {
  const SidebarCollapsePreference._();

  static const key = 'sidebar_collapsed';

  static Future<bool> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> write(bool collapsed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, collapsed);
    } catch (_) {
      // Not worth a message: the sidebar still collapses for this session.
    }
  }
}

class _SidebarPanel extends StatelessWidget {
  const _SidebarPanel({
    required this.shell,
    required this.markers,
    required this.collapsed,
    required this.closeDrawerOnSelect,
    this.onToggleCollapsed,
  });

  final AppShell shell;
  final Map<int, int> markers;
  final bool collapsed;
  final bool closeDrawerOnSelect;

  /// Null in the drawer and when the window itself forces the rail, so the
  /// button never offers a shape the window cannot show.
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewmodel>();
    final name = auth.user?.fullName ?? shell.fallbackUserName;
    final role = auth.user?.roleLabel ?? shell.fallbackRoleLabel;
    final onSelected = shell.onDestinationSelected;

    return Material(
      color: AppColors.chrome,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _SidebarGridPainter()),
            ),
          ),
          Column(
            children: [
              SizedBox(
                height: AppShell.headerHeight,
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: collapsed
                            ? const SystemBrand(logoSize: 40, showName: false)
                            : const SystemBrand(
                                logoSize: 42,
                                fontSize: 14,
                                subtitle: '& CONSTRUCTION SUPPLIES',
                                textColor: AppColors.brandWhite,
                                subtitleColor: AppColors.brandGold,
                              ),
                      ),
                    ),
                    if (onToggleCollapsed case final toggle?)
                      IconButton(
                        tooltip: collapsed
                            ? 'Expand sidebar'
                            : 'Collapse sidebar',
                        onPressed: toggle,
                        icon: Icon(
                          collapsed ? Icons.chevron_right : Icons.chevron_left,
                          size: 18,
                          color: AppColors.chromeText,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.chromeBorder),
              Expanded(
                child: SharedSidebar(
                  sections: shell.sections,
                  selectedIndex: shell.selectedIndex,
                  collapsed: collapsed,
                  markers: markers,
                  onDestinationSelected: onSelected == null
                      ? null
                      : (index) {
                          if (closeDrawerOnSelect) Navigator.of(context).pop();
                          onSelected(index);
                        },
                ),
              ),
              const Divider(height: 1, color: AppColors.chromeBorder),
              if (collapsed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    children: [
                      Tooltip(
                        message: '$name · $role',
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.chromeRaised,
                          foregroundColor: AppColors.brandGoldLight,
                          child: Text(
                            _initials(name),
                            // Initials are a heading: the brand face, not the
                            // platform font the bare TextStyle fell back to.
                            style: const TextStyle(
                              fontFamily: AppTextStyles.cinzelFont,
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
                        color: AppColors.chromeText,
                      ),
                    ],
                  ),
                )
              else
                // The signed-in account, on the raised dark surface the rest of
                // the chrome is drawn on.
                // The signed-in account, on the raised dark surface the rest
                // of the chrome is drawn on. The tile paints its own
                // background: a ListTile inside a coloured box hides its ink
                // splashes, and the framework asserts on exactly that.
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: ListTile(
                    tileColor: AppColors.chromeRaised,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.medium),
                      side: const BorderSide(color: AppColors.chromeBorder),
                    ),
                    title: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.brandWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      role,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.brandGold,
                        fontSize: 11,
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: 'Log out',
                      onPressed: auth.logout,
                      icon: const Icon(Icons.logout, size: 18),
                      color: AppColors.chromeText,
                    ),
                  ),
                ),
            ],
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
    return SizedBox(
      height: AppShell.headerHeight,
      child: ColoredBox(
        color: AppColors.cardBackground,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: showMenuButton ? AppSpacing.sm : AppSpacing.xl,
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
              ),
            ),
            // The tape-measure edge the design system uses on brand surfaces.
            const MeasureRuler(height: 7),
          ],
        ),
      ),
    );
  }
}

/// The faint blueprint grid the dark chrome carries, so the sidebar reads as
/// one drawn surface rather than a flat black band.
class _SidebarGridPainter extends CustomPainter {
  const _SidebarGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    Blueprint.paintGrid(canvas, size, opacity: 0.55);
  }

  @override
  bool shouldRepaint(covariant _SidebarGridPainter oldDelegate) => false;
}
