import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Sends a store-manager sidebar index to its own route, from the registry.
///
/// The index is the destination's POSITION in `AppDestinations.forArea(sales)`
/// (SharedSidebar numbers destinations across sections, 0-based, ignoring
/// section headings). Sidebar and routes used to be two separate literals that
/// could drift — index 6 (Reports) once fell outside the map and was a silent
/// no-op (D-01); reading the same registry row removes that class of bug.
void navigateSales(BuildContext context, int index) {
  final path = AppDestinations.routeAt(AppAreas.sales, index);
  if (path != null) context.go(path);
}
