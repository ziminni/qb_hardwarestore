// Window widths at which the app shell changes shape.
//
// Measured against the whole window, not the content area, so every role's
// shell switches at the same moment when the window is resized.
class AppBreakpoints {
  AppBreakpoints._();

  /// At or above this width the sidebar shows icons and labels.
  static const double expanded = 1200;

  /// At or above this width (and below [expanded]) the sidebar collapses to an
  /// icon rail. Below it the sidebar moves into a drawer behind a menu button.
  static const double rail = 900;
}

enum ShellMode { expanded, rail, compact }

ShellMode shellModeFor(double width) {
  if (width >= AppBreakpoints.expanded) return ShellMode.expanded;
  if (width >= AppBreakpoints.rail) return ShellMode.rail;
  return ShellMode.compact;
}
