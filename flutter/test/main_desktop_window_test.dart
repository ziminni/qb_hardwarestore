// The Bodega Checker's Android phone showed only a black screen (2026-11-18):
// main() set up the desktop window on every platform but the web, and on a
// phone window_manager's first call never returns, so runApp never ran.

import 'package:client/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only Mac, Windows and Linux get the desktop window set-up', () {
    for (final platform in TargetPlatform.values) {
      final desktop = {
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      }.contains(platform);
      expect(
        runsInDesktopWindow(isWeb: false, platform: platform),
        desktop,
        reason: '$platform',
      );
    }
  });

  test('a phone never touches window_manager', () {
    expect(
      runsInDesktopWindow(isWeb: false, platform: TargetPlatform.android),
      isFalse,
    );
    expect(
      runsInDesktopWindow(isWeb: false, platform: TargetPlatform.iOS),
      isFalse,
    );
  });

  test('the web build never touches it either', () {
    expect(
      runsInDesktopWindow(isWeb: true, platform: TargetPlatform.macOS),
      isFalse,
    );
  });
}
