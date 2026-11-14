import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// How every scrollable in the app scrolls.
///
/// Flutter's stock behavior ignores a mouse DRAG and maps the mouse wheel to the
/// vertical axis, and on desktop/web its scrollbar only appears on hover. Every
/// data table here is a horizontal scroll view (low stock, products, purchases,
/// suppliers, stock, movements...), so on a 1366px laptop with a plain mouse
/// the right-hand columns — usually Actions, with Reorder and Resolve — could
/// not be reached at all. Phase 4 browser QA found it on the low-stock screen.
///
/// Two changes, nothing else:
///
/// * every pointer kind may drag-scroll, the mouse included;
/// * a HORIZONTAL scrollbar is always visible, so the clerk can see that the
///   table continues and can grab the thumb. Vertical scrollbars keep the
///   platform default — pages already scroll with the wheel.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (axisDirectionToAxis(details.direction) == Axis.horizontal) {
      return Scrollbar(
        controller: details.controller,
        thumbVisibility: true,
        child: child,
      );
    }
    return super.buildScrollbar(context, child, details);
  }
}
