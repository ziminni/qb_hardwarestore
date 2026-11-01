import 'package:clock/clock.dart';

/// What "now" means to every screen in the app.
///
/// Production reads the wall clock: `const Clock()` is the real one. A test file
/// pins it once, in `test/flutter_test_config.dart`, so the screens that default
/// to "today", "this week" or "this month" - and the goldens that show them - do
/// not change their output when the wall clock crosses a day, week or month
/// boundary.
///
/// `package:clock`'s zone-based `withClock` cannot do this job here: the test
/// runner discards the zone a test file's `main` runs in, so a value set there
/// never reaches the widget tree. One variable set per test file does.
Clock appClock = const Clock();
