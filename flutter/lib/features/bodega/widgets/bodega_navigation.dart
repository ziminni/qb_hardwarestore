import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Maps a Bodega sidebar index to its route, from the registry.
void navigateBodega(BuildContext context, int index) {
  final path = AppDestinations.routeAt(AppAreas.bodega, index);
  if (path != null) context.go(path);
}
