import 'dart:async';

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/constants/app_breakpoints.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/navigation/merged_sidebar.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/widget/area_switcher_menu.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:client/shared/widgets/measure_ruler.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
    this.originArea,
    this.selectedId,
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

  /// The flat index of the open page in [originArea]'s own menu.
  ///
  /// An account that holds several areas sees ONE merged list, whose positions
  /// have nothing to do with this number; the shell passes [originArea] so the
  /// page can still be found by identity (its row id) and highlighted.
  final int selectedIndex;

  /// The area whose menu [selectedIndex] indexes ([AppAreas] code). Only the
  /// merged list reads it; a single-area account keeps its own menu untouched.
  final String? originArea;

  /// The page to highlight, by destination id, when the caller knows the
  /// identity rather than a position - the combined landing page (F4) belongs to
  /// no single area's menu, so it has no origin index to derive one from. Wins
  /// over [originArea] + [selectedIndex] in the merged list.
  final String? selectedId;
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

  /// The areas this account holds, in [MergedSidebar.headingOrder]; more than
  /// one means the sidebar is the single merged list.
  List<String> _areas = const [];

  /// The merged list's live counts, keyed by destination id. Filled by the one
  /// read started in [didChangeDependencies].
  Map<String, int> _mergedMarkers = const {};

  bool _markersStarted = false;

  /// The user's choice from the collapse button. Only consulted on a window
  /// wide enough to show the full sidebar ([AppBreakpoints.expanded]); a
  /// narrow window and the drawer ignore it. Defaults to collapsed.
  bool _collapsedByUser = true;

  @override
  void initState() {
    super.initState();
    _restoreCollapse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _areas = MergedSidebar.heldAreas(
      context.watch<AuthViewmodel>().assignedAreas,
    );
    if (_markersStarted) return;
    _markersStarted = true;
    _refreshMarkers();
    // Badges stay live while the shell is open: a request CPMS sends raises
    // the "waiting" count on any page, with no re-login.
    _markerTimer = Timer.periodic(markerRefreshEvery, (_) => _refreshMarkers());
  }

  /// How often the sidebar badges are read again while the shell is open.
  static const Duration markerRefreshEvery = Duration(seconds: 15);

  Timer? _markerTimer;

  @override
  void dispose() {
    _markerTimer?.cancel();
    super.dispose();
  }

  void _refreshMarkers() {
    if (!mounted) return;
    if (_areas.length > 1) {
      // The merged list shows every held area's badge, so it runs those areas'
      // own queries once instead of the shell's single one.
      _loadMergedMarkers(_areas);
    } else if (widget.markers == null) {
      // A caller that supplies its own counts owns them; a second read here
      // would be a duplicate request whose answer the caller cannot see.
      _loadMarkers();
    }
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

  /// Every held area's badge, read once. The area whose page supplies its own
  /// live count is skipped: that page's number is authoritative and a second
  /// query for it would be a duplicate request.
  Future<void> _loadMergedMarkers(List<String> areas) async {
    final origin = widget.originArea;
    final pageOwnsItsCount = widget.markers != null && origin != null;
    final counts = await MergedSidebar.loadMergedBadges([
      for (final area in areas)
        if (!pageOwnsItsCount || area != origin) area,
    ]);
    if (!mounted) return;
    setState(() => _mergedMarkers = counts);
  }

  /// The page's own live counts, re-keyed from its area's flat indices to the
  /// merged list's destination ids. Read on every build, so a count the page
  /// resolved clears its row without leaving the screen.
  Map<String, int> _pageMarkersById() {
    final markers = widget.markers;
    final area = widget.originArea;
    if (markers == null || area == null) return const {};
    final rows = AppDestinations.forArea(area);
    return {
      for (final entry in markers.entries)
        if (entry.key >= 0 && entry.key < rows.length)
          rows[entry.key].id: entry.value,
    };
  }

  /// The id of the page the shell was built for, from its own area's row at
  /// [AppShell.selectedIndex]. Null when the shell has no origin area (the
  /// combined landing page, F4) or the index is outside that menu.
  String? _selectedId() {
    final area = widget.originArea;
    if (area == null) return null;
    final rows = AppDestinations.forArea(area);
    final index = widget.selectedIndex;
    if (index < 0 || index >= rows.length) return null;
    return rows[index].id;
  }

  /// A merged row opens the route of the area that owns it - the widest one - so
  /// Admin's Payables and the Store Manager's Payables never disagree about
  /// where the single row goes.
  void _openMerged(List<AppDestination> rows, int index) {
    if (index < 0 || index >= rows.length) return;
    context.go(rows[index].route);
  }

  Future<void> _toggleCollapsed() async {
    setState(() => _collapsedByUser = !_collapsedByUser);
    await SidebarCollapsePreference.write(_collapsedByUser);
  }

  @override
  Widget build(BuildContext context) {
    // An account holding more than one area gets ONE list: the four menus
    // merged, a shared page once under the widest area. Single-area accounts
    // keep exactly the menu their shell built.
    final merged = _areas.length > 1;
    final mergedRows = merged
        ? MergedSidebar.rows(_areas)
        : const <AppDestination>[];
    final sections = merged
        ? MergedSidebar.sectionsFor(mergedRows)
        : widget.sections;
    final selectedId = merged ? widget.selectedId ?? _selectedId() : null;
    final markersById = merged
        ? {..._mergedMarkers, ..._pageMarkersById()}
        : const <String, int>{};
    // The flat-index counts cannot be reused in a list whose positions have
    // changed: in merged mode only the id-keyed counts are drawn.
    final markers = merged ? const <int, int>{} : _markers;
    final onDestinationSelected = merged
        ? (int index) => _openMerged(mergedRows, index)
        : widget.onDestinationSelected;

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

        _SidebarPanel panel({required bool collapsed, required bool close}) =>
            _SidebarPanel(
              fallbackUserName: widget.fallbackUserName,
              fallbackRoleLabel: widget.fallbackRoleLabel,
              sections: sections,
              selectedIndex: widget.selectedIndex,
              selectedId: selectedId,
              markers: markers,
              markersById: markersById,
              onDestinationSelected: onDestinationSelected,
              collapsed: collapsed,
              closeDrawerOnSelect: close,
              onToggleCollapsed: !close && mode == ShellMode.expanded
                  ? _toggleCollapsed
                  : null,
            );

        final p = AppPalette.of(context);
        final sidebarWidth = rail
            ? SharedSidebar.railWidth
            : SharedSidebar.width;
        final canToggleSidebar = !compact && mode == ShellMode.expanded;
        return Scaffold(
          backgroundColor: p.background,
          drawer: compact
              ? Drawer(
                  width: SharedSidebar.width,
                  backgroundColor: p.sidebarBg,
                  shape: const RoundedRectangleBorder(),
                  child: panel(collapsed: false, close: true),
                )
              : null,
          body: Stack(
            children: [
              Row(
                children: [
                  if (!compact)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOutCubic,
                      width: sidebarWidth,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        // Sidebar chrome with a hairline border against the page.
                        color: p.sidebarBg,
                        border: Border(
                          right: BorderSide(color: p.sidebarBorder),
                        ),
                      ),
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: sidebarWidth,
                        maxWidth: sidebarWidth,
                        child: panel(collapsed: rail, close: false),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        _Header(
                          shell: widget,
                          showMenuButton: compact,
                          // The merged list replaces the switcher: one menu already
                          // holds every area (decision 24, ruling 1).
                          showAreaSwitcher: !merged,
                        ),
                        Expanded(child: body),
                      ],
                    ),
                  ),
                ],
              ),
              if (canToggleSidebar)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOutCubic,
                  left: sidebarWidth - 5,
                  top: 0,
                  bottom: 0,
                  width: 10,
                  child: _SidebarEdgeToggle(
                    collapsed: rail,
                    onToggle: _toggleCollapsed,
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
      return prefs.getBool(key) ?? true;
    } catch (_) {
      return true;
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
    required this.fallbackUserName,
    required this.fallbackRoleLabel,
    required this.sections,
    required this.selectedIndex,
    required this.selectedId,
    required this.markers,
    required this.markersById,
    required this.onDestinationSelected,
    required this.collapsed,
    required this.closeDrawerOnSelect,
    this.onToggleCollapsed,
  });

  final String fallbackUserName;
  final String fallbackRoleLabel;
  final List<SharedSidebarSection> sections;
  final int selectedIndex;
  final String? selectedId;
  final Map<int, int> markers;
  final Map<String, int> markersById;
  final ValueChanged<int>? onDestinationSelected;
  final bool collapsed;
  final bool closeDrawerOnSelect;

  /// Null in the drawer and when the window itself forces the rail, so the
  /// button never offers a shape the window cannot show.
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewmodel>();
    final p = AppPalette.of(context);
    final name = auth.user?.fullName ?? fallbackUserName;
    final role = auth.user?.roleLabel ?? fallbackRoleLabel;
    final onSelected = onDestinationSelected;
    final nameColor = p.sidebarIsLight ? p.textPrimary : AppColors.brandWhite;

    return Material(
      color: p.sidebarBg,
      child: GestureDetector(
        key: const ValueKey('sidebar-free-space-detector'),
        behavior: HitTestBehavior.opaque,
        onTap: collapsed ? onToggleCollapsed : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _SidebarGridPainter(
                    accent: p.accent,
                    isLight: p.sidebarIsLight,
                  ),
                ),
              ),
            ),
            Column(
              children: [
                _SidebarBrandHeader(
                  collapsed: collapsed,
                  onToggleCollapsed: onToggleCollapsed,
                ),
              Expanded(
                child: SharedSidebar(
                  sections: sections,
                  selectedIndex: selectedIndex,
                  selectedId: selectedId,
                  collapsed: collapsed,
                  markers: markers,
                  markersById: markersById,
                  onDestinationSelected: onSelected == null
                      ? null
                      : (index) {
                          if (closeDrawerOnSelect) Navigator.of(context).pop();
                          onSelected(index);
                        },
                ),
              ),
              Divider(height: 1, color: p.sidebarBorder),
              if (collapsed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Column(
                    children: [
                      Tooltip(
                        message: '$name · $role',
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: p.accent.withValues(alpha: 0.5),
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 16,
                            backgroundColor: p.sidebarRaised,
                            foregroundColor: p.sidebarActiveText,
                            child: Text(
                              _initials(name),
                              // Initials are a heading: the brand face, not the
                              // platform font the bare TextStyle fell back to.
                              style: const TextStyle(
                                fontFamily: AppTextStyles.cinzelFont,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _ChromeIconButton(
                        tooltip: 'Log out',
                        icon: Icons.logout_rounded,
                        onPressed: auth.logout,
                      ),
                    ],
                  ),
                )
              else
                // The signed-in account on the raised chrome surface. The tile
                // paints its own background so ink splashes render properly.
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: ListTile(
                    leading: ClipPath(
                      clipper: const HexagonClipper(),
                      child: ColoredBox(
                        color: p.accent,
                        child: SizedBox.square(
                          dimension: 36,
                          child: Center(
                            child: Text(
                              _initials(name),
                              style: TextStyle(
                                fontFamily: AppTextStyles.outfitFont,
                                color: p.onAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    horizontalTitleGap: 10,
                    contentPadding: const EdgeInsets.fromLTRB(10, 2, 6, 2),
                    tileColor: p.sidebarRaised,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.medium),
                      side: BorderSide(color: p.sidebarBorder),
                    ),
                    title: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelLarge.copyWith(
                        color: nameColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    subtitle: Text(
                      role,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: p.sidebarSubtitle,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    trailing: _ChromeIconButton(
                      tooltip: 'Log out',
                      icon: Icons.logout_rounded,
                      onPressed: auth.logout,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
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

class _SidebarBrandHeader extends StatelessWidget {
  const _SidebarBrandHeader({
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    const logoSize = 30.0;
    final titleColor = p.sidebarIsLight ? p.textPrimary : AppColors.brandWhite;
    final logoTile = Container(
      width: 38,
      height: 38,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.brandWhite,
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: Border.all(color: p.accent.withValues(alpha: 0.48)),
      ),
      child: Image.asset(
        AppAssets.logo,
        width: logoSize,
        height: logoSize,
        fit: BoxFit.contain,
        cacheWidth: (logoSize * dpr).round(),
        semanticLabel: 'Queen Builders logo',
      ),
    );

    final brandContent = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 4 : 6,
        vertical: 4,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: collapsed ? Alignment.center : Alignment.centerLeft,
        child: collapsed
            ? logoTile
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  logoTile,
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QUEEN BUILDERS',
                        style: AppTextStyles.h4.copyWith(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                          letterSpacing: 0.75,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '& CONSTRUCTION SUPPLIES',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: p.sidebarSubtitle,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.65,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );

    final toggle = onToggleCollapsed;
    Widget interactiveBrand = toggle == null
        ? brandContent
        : Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.medium),
            child: InkWell(
              key: const ValueKey('sidebar-brand-toggle'),
              onTap: toggle,
              borderRadius: BorderRadius.circular(AppRadii.medium),
              hoverColor: p.accent.withValues(alpha: 0.14),
              child: brandContent,
            ),
          );
    if (toggle != null && collapsed) {
      interactiveBrand = Tooltip(
        message: 'Expand sidebar',
        child: interactiveBrand,
      );
    }

    return Container(
      height: AppShell.headerHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.sidebarRaised.withValues(alpha: 0.95), p.sidebarBg],
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: collapsed ? 8 : AppSpacing.sm + 2,
              ),
              child: collapsed
                  ? Align(
                      alignment: Alignment.center,
                      child: interactiveBrand,
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: interactiveBrand,
                          ),
                        ),
                        if (toggle != null) ...[
                          const SizedBox(width: 6),
                          _ChromeIconButton(
                            key: const ValueKey('sidebar-collapse-button'),
                            tooltip: 'Collapse sidebar',
                            icon: Icons.chevron_left_rounded,
                            onPressed: toggle,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
          // Architectural accent hairline anchoring the brand header.
          Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [p.accent.withValues(alpha: 0.65), p.sidebarBorder],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Interactive seam along the sidebar's right border. Hovering shows the
/// directional resize cursor and highlights the vertical line so it reads
/// unmistakably as a sidebar toggle rather than a page click.
class _SidebarEdgeToggle extends StatefulWidget {
  const _SidebarEdgeToggle({required this.collapsed, required this.onToggle});

  final bool collapsed;
  final VoidCallback onToggle;

  @override
  State<_SidebarEdgeToggle> createState() => _SidebarEdgeToggleState();
}

class _SidebarEdgeToggleState extends State<_SidebarEdgeToggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 140);

    return Semantics(
      key: const ValueKey('sidebar-edge-toggle'),
      button: true,
      label: widget.collapsed ? 'Expand sidebar' : 'Collapse sidebar',
      child: MouseRegion(
        cursor: widget.collapsed
            ? SystemMouseCursors.resizeRight
            : SystemMouseCursors.resizeLeft,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onToggle,
          child: Center(
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              width: _hovered ? 3 : 1,
              decoration: BoxDecoration(
                color: _hovered ? p.accent : Colors.transparent,
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: p.accent.withValues(alpha: 0.35),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChromeIconButton extends StatelessWidget {
  const _ChromeIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  static const double _size = 32;
  static const double _iconSize = 17;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SizedBox(
      width: _size,
      height: _size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: _size, height: _size),
        style: IconButton.styleFrom(
          backgroundColor: p.sidebarRaised,
          foregroundColor: p.sidebarText,
          hoverColor: p.accent.withValues(alpha: 0.14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.small),
            side: BorderSide(color: p.sidebarBorder),
          ),
        ),
        icon: Icon(icon, size: _iconSize),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.shell,
    required this.showMenuButton,
    required this.showAreaSwitcher,
  });

  final AppShell shell;
  final bool showMenuButton;

  /// False for a merged sidebar: the one list already holds every assigned
  /// area, so switching areas would only re-render the same menu (decision 24,
  /// ruling 1). Single-area accounts keep today's behaviour.
  final bool showAreaSwitcher;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final hasSubtitle = shell.subtitle.trim().isNotEmpty;

    return SizedBox(
      height: AppShell.headerHeight,
      child: ColoredBox(
        color: p.cardBackground,
        child: Column(
          children: [
            // Thin signature accent edge echoing the login card crown.
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    p.accent,
                    p.accentLight,
                    p.accent.withValues(alpha: 0.25),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: showMenuButton ? AppSpacing.md : AppSpacing.xl,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final hasSwitcher =
                        showAreaSwitcher &&
                        context.select<AuthViewmodel, bool>(
                          (auth) => auth.assignedAreaRoles.length >= 2,
                        );
                    final hasTrailingActions =
                        hasSwitcher || shell.actions.isNotEmpty;
                    // Show the date pill only when the header has comfortable
                    // horizontal room for the title, date, and actions without
                    // truncating any of them.
                    final minWidthForDate = shell.actions.length >= 3
                        ? 1360.0
                        : shell.actions.length >= 2
                        ? 1060.0
                        : 640.0;
                    final showDatePill =
                        !showMenuButton &&
                        constraints.maxWidth >= minWidthForDate;

                    return Row(
                      children: [
                        if (showMenuButton) ...[
                          SizedBox(
                            width: 38,
                            height: 38,
                            child: IconButton(
                              tooltip: 'Open menu',
                              onPressed: () =>
                                  Scaffold.of(context).openDrawer(),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                backgroundColor: p.surfaceSunken,
                                foregroundColor: p.textPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.small,
                                  ),
                                  side: BorderSide(color: p.border),
                                ),
                              ),
                              icon: const Icon(Icons.menu_rounded, size: 20),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                        ],
                        Container(
                          width: 3.5,
                          height: hasSubtitle ? 32 : 22,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [p.accent, p.accentLight],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Single Expanded: fills all free width so the date
                        // pill and action buttons always anchor flush right.
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shell.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.h3.copyWith(
                                  fontFamily: AppTextStyles.cinzelFont,
                                  fontSize: showMenuButton ? 17 : 19,
                                  fontWeight: FontWeight.w700,
                                  color: p.textPrimary,
                                  letterSpacing: 0.35,
                                  height: 1.15,
                                ),
                              ),
                              if (hasSubtitle) ...[
                                const SizedBox(height: 1),
                                Text(
                                  shell.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    fontSize: 12,
                                    color: p.textSecondary,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (showDatePill) ...[
                          const SizedBox(width: AppSpacing.md),
                          _HeaderDatePill(palette: p),
                          if (hasTrailingActions) ...[
                            const SizedBox(width: AppSpacing.md),
                            Container(width: 1, height: 22, color: p.border),
                          ],
                        ],
                        // Multi-area staff switch areas from here (Phase 4 F3b).
                        // Single-area accounts still mount the widget (it draws
                        // SizedBox.shrink()); a merged account retires it.
                        if (hasSwitcher) const SizedBox(width: AppSpacing.md),
                        if (showAreaSwitcher) const AreaSwitcherMenu(),
                        if (shell.actions.isNotEmpty) ...[
                          SizedBox(
                            width: hasSwitcher ? AppSpacing.sm : AppSpacing.md,
                          ),
                          ...shell.actions,
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
            // The tape-measure edge the design system uses on brand surfaces.
            Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: p.border.withValues(alpha: 0.7)),
                ),
              ),
              child: MeasureRuler(height: 6, color: p.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// Today's date chip shown on desktop headers when there is enough room.
class _HeaderDatePill extends StatelessWidget {
  const _HeaderDatePill({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 13.5,
            color: palette.accentInk,
          ),
          const SizedBox(width: 7),
          Text(
            formatWeekdayDate(appClock.now()),
            maxLines: 1,
            style: AppTextStyles.labelMedium.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// The faint blueprint grid and warm glow the sidebar carries, linked to the
/// login screen's architectural drafting canvas.
class _SidebarGridPainter extends CustomPainter {
  const _SidebarGridPainter({required this.accent, required this.isLight});

  final Color accent;
  final bool isLight;

  @override
  void paint(Canvas canvas, Size size) {
    final glowRect = Rect.fromCircle(
      center: Offset(size.width * 0.2, 48),
      radius: size.width * 1.15,
    );
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: isLight ? 0.05 : 0.08),
          Colors.transparent,
        ],
      ).createShader(glowRect);
    canvas.drawRect(Offset.zero & size, glowPaint);

    Blueprint.paintGrid(
      canvas,
      size,
      opacity: isLight ? 0.28 : 0.48,
      color: accent,
    );
  }

  @override
  bool shouldRepaint(covariant _SidebarGridPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.isLight != isLight;
}
