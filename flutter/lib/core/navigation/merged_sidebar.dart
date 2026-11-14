import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';

/// One live count, read once per area that owns a badge row.
typedef BadgeCountLoader = Future<int> Function();

/// Live queued carts: the Till's "Held transactions" count.
Future<int> heldCartsCount() async =>
    (await HeldCartService().fetchAll()).length;

/// Unresolved stock alerts: the Stock Manager's "Low stock" count.
Future<int> unresolvedAlertsCount() async => (await InventoryRepository(
  InventoryService(),
).loadAlerts()).where((alert) => !alert.isResolved).length;

/// Project requests waiting for a decision: the shared Admin/Sales count.
Future<int> waitingProjectRequestsCount() =>
    RequisitionRepository().waitingCount();

/// The badge query of each area that has one. Admin and Sales share a row, so
/// they share a query: [MergedSidebar.loadMergedBadges] keeps the widest area's
/// answer instead of adding the two.
const Map<String, BadgeCountLoader> badgeLoaders = {
  AppAreas.pos: heldCartsCount,
  AppAreas.inventory: unresolvedAlertsCount,
  AppAreas.admin: waitingProjectRequestsCount,
  AppAreas.sales: waitingProjectRequestsCount,
};

/// The one sidebar a multi-area account gets (Phase 2 F2, decision 24).
///
/// Areas render in daily-work order (Till, Sales, Stock, Admin) and a page that
/// exists in several areas is drawn ONCE, under the WIDEST held area
/// (admin > sales > inventory > pos) and with that area's label and route.
/// De-duplication keys off [AppDestination.sharedKey], never a label: Stock's
/// "Reports" is a different page from the Admin/Sales one and stays.
///
/// Single-area accounts never reach this file: their shell keeps its own menu.
class MergedSidebar {
  const MergedSidebar._();

  /// The merged landing page's stable id (F4's combined dashboard).
  static const String combinedDashboardId = 'combined.dashboard';

  /// The landing row: one page of every area's "needs you" tiles, drawn ABOVE
  /// the Till heading because it belongs to no single area.
  ///
  /// It is merged-only on purpose and NOT a row of [AppDestinations.all]: the
  /// four single-role menus and their twelve goldens must not grow an entry.
  /// Its [AppDestination.area] is a sentinel, `home`, which no [AppAreas] code
  /// equals - that is what starts an unlabelled section around it.
  static const String homeArea = 'home';

  static const AppDestination landing = AppDestination(
    id: combinedDashboardId,
    area: homeArea,
    label: 'Needs you',
    icon: Icons.space_dashboard_outlined,
    route: AppRoutes.combinedDashboard,
  );

  /// Rendering order: the daily work first, the back office last.
  static const List<String> headingOrder = [
    AppAreas.pos,
    AppAreas.sales,
    AppAreas.inventory,
    AppAreas.admin,
  ];

  /// The heading each area's block carries in the merged list.
  static const Map<String, String> areaHeadings = {
    AppAreas.pos: 'Till',
    AppAreas.sales: 'Sales',
    AppAreas.inventory: 'Stock',
    AppAreas.admin: 'Admin',
  };

  /// The assigned areas that exist, de-duplicated, in [headingOrder].
  ///
  /// The auth model already drops unknown codes; this repeats the check because
  /// the sidebar is the one place a stale code would draw an empty block.
  static List<String> heldAreas(List<String> assigned) {
    final valid = {
      for (final area in assigned)
        if (AppAreas.contains(area)) area,
    };
    return [
      for (final area in headingOrder)
        if (valid.contains(area)) area,
    ];
  }

  /// Every row the merged sidebar draws, in rendering order: the landing row,
  /// then the held areas' rows.
  ///
  /// A shared page is kept only under the widest held area that owns it, so its
  /// label and route come from that area. Every non-shared row is kept as is.
  static List<AppDestination> rows(List<String> areas) {
    final held = heldAreas(areas);
    final widestOwner = <String, String>{};
    for (final area in held) {
      for (final row in AppDestinations.forArea(area)) {
        final key = row.sharedKey;
        if (key == null) continue;
        final owner = widestOwner[key];
        if (owner == null ||
            AppAreas.codes.indexOf(area) < AppAreas.codes.indexOf(owner)) {
          widestOwner[key] = area;
        }
      }
    }
    return [
      // One landing page per merged account, and none at all for a single area
      // (that account keeps its own dashboard, which its menu already shows).
      if (held.length > 1) landing,
      for (final area in held)
        for (final row in AppDestinations.forArea(area))
          if (row.sharedKey == null || widestOwner[row.sharedKey] == area) row,
    ];
  }

  /// [rows] as the sidebar renders them: the unlabelled landing row first, then
  /// one section per area.
  ///
  /// The section heading names the AREA (not the row's own sub-heading): with
  /// four menus in one list, "Selling" would appear three times and explain
  /// nothing. Rows keep their own order inside their block.
  static List<SharedSidebarSection> sectionsFor(List<AppDestination> rows) {
    final sections = <SharedSidebarSection>[];
    var start = 0;
    for (var index = 1; index <= rows.length; index++) {
      final boundary =
          index == rows.length || rows[index].area != rows[start].area;
      if (!boundary) continue;
      sections.add(
        SharedSidebarSection(
          label: areaHeadings[rows[start].area] ?? '',
          destinations: [
            for (final row in rows.sublist(start, index))
              SharedSidebarDestination(
                id: row.id,
                label: row.label,
                icon: row.icon,
              ),
          ],
        ),
      );
      start = index;
    }
    return sections;
  }

  /// The live counts to draw on [areas]' merged rows, keyed by destination id.
  ///
  /// Runs ONE query per held area that owns a badge (each area's own loader), so
  /// a merged sidebar does not load the same queue twice. A shared row keeps the
  /// WIDEST area's number rather than the sum: the row is one page, so 7 waiting
  /// requests are 7, not 7 + 7. A failed query leaves its row blank, and a zero
  /// is dropped here because the sidebar draws nothing for it anyway.
  static Future<Map<String, int>> loadMergedBadges(
    List<String> areas, {
    Map<String, BadgeCountLoader> loaders = badgeLoaders,
  }) async {
    final counts = <String, int>{};
    final owners = <String, int>{};
    await Future.wait([
      for (final area in heldAreas(areas))
        if (loaders[area] case final load?)
          () async {
            final id = _badgeIdOf(area);
            if (id == null) return;
            final int count;
            try {
              count = await load();
            } catch (_) {
              // A sidebar count is a convenience, never the page's own data: a
              // failed read shows nothing instead of a zero claiming an empty
              // queue.
              return;
            }
            if (count <= 0) return;
            final rank = AppAreas.codes.indexOf(area);
            if (counts.containsKey(id) && owners[id]! <= rank) return;
            owners[id] = rank;
            counts[id] = count;
          }(),
    ]);
    return counts;
  }

  /// The id of [area]'s own badged row, or null when that area has none.
  static String? _badgeIdOf(String area) {
    for (final row in AppDestinations.forArea(area)) {
      if (row.badge) return row.id;
    }
    return null;
  }
}
