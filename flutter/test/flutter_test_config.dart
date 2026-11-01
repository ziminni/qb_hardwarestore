// Every test, goldens included, runs at one fixed mid-month instant.
//
// `appClock` is the app's only source of "now", so pinning it here keeps the
// screens that default to "this month" / "today" / "this week" - and the goldens
// that show them - from changing their output when the wall clock crosses a
// month, week or day boundary.
//
// Mid-month at 10:00 on purpose: a plain weekday, far from every boundary in
// either direction, so a test that builds a row "an hour ago" or "30 days from
// now" stays inside the period the screen is showing.
import 'dart:async';

import 'package:client/core/time/app_clock.dart';
import 'package:clock/clock.dart';

/// Wednesday, 15 October 2026, 10:00.
final DateTime testNow = DateTime(2026, 10, 15, 10);

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  appClock = Clock.fixed(testNow);
  await testMain();
}
