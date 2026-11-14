import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Maps a stocker sidebar destination index to its route and navigates there,
/// from the registry (Phase 2 F1).
///
/// The index is the destination's POSITION in the stock manager's rows of
/// [AppDestinations] (SharedSidebar numbers destinations across sections, 0-based,
/// ignoring section headings). Sidebar and routes used to be two separate
/// literals and they DID drift: Receiving sat on index 9, which the sidebar
/// renders as "Returns", so the Returns tab opened the Receiving screen. Reading
/// one row for both removes that class of bug.
///
/// `test/features/inventory/inventory_returns_routing_test.dart` still walks every
/// index through a real router, so a route that goes nowhere fails a test.
void navigateInventory(BuildContext context, int index) {
  final path = AppDestinations.routeAt(AppAreas.inventory, index);
  if (path != null) context.go(path);
}
