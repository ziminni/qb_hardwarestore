import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every text slot the app reaches through `theme.textTheme` must name one of
/// the two brand families. A slot the theme leaves unset silently falls back to
/// the platform font (Roboto), which is how the shell header, the notification
/// badge and about fifty other call sites rendered in the wrong face.
void main() {
  final textTheme = AppTheme.lightTheme.textTheme;

  /// The whole Material 3 scale, named, so a missing slot shows up by name
  /// instead of as a null somewhere in a screen.
  final slots = <String, TextStyle?>{
    'displayLarge': textTheme.displayLarge,
    'displayMedium': textTheme.displayMedium,
    'displaySmall': textTheme.displaySmall,
    'headlineLarge': textTheme.headlineLarge,
    'headlineMedium': textTheme.headlineMedium,
    'headlineSmall': textTheme.headlineSmall,
    'titleLarge': textTheme.titleLarge,
    'titleMedium': textTheme.titleMedium,
    'titleSmall': textTheme.titleSmall,
    'bodyLarge': textTheme.bodyLarge,
    'bodyMedium': textTheme.bodyMedium,
    'bodySmall': textTheme.bodySmall,
    'labelLarge': textTheme.labelLarge,
    'labelMedium': textTheme.labelMedium,
    'labelSmall': textTheme.labelSmall,
  };

  /// The slots lib actually reads (grep `textTheme\.\w+`). Filling only these
  /// is not enough for correctness, but these are the ones a regression would
  /// show up in first.
  const usedInLib = [
    'displayLarge',
    'headlineMedium',
    'headlineSmall',
    'titleLarge',
    'titleMedium',
    'titleSmall',
    'bodyMedium',
    'bodySmall',
    'labelLarge',
    'labelMedium',
    'labelSmall',
  ];

  test('every text slot the app uses names a brand font family', () {
    for (final name in usedInLib) {
      final style = slots[name];
      expect(style, isNotNull, reason: '$name is not styled at all');
      expect(
        style!.fontFamily,
        anyOf(AppTextStyles.cinzelFont, AppTextStyles.outfitFont),
        reason: '$name falls back to the platform font',
      );
    }
  });

  test('every styled slot keeps the theme rule: 18 px and up is Cinzel', () {
    // The theme's own rule, read off h1 to h4 and the body and label styles:
    // headings (18 px and larger) are Cinzel, content (16 px and smaller) is
    // Open Sans. New slots follow it rather than inventing a third rule.
    for (final entry in slots.entries) {
      final style = entry.value;
      if (style == null) continue;
      final size = style.fontSize ?? 0;
      expect(
        style.fontFamily,
        size >= 18 ? AppTextStyles.cinzelFont : AppTextStyles.outfitFont,
        reason: '${entry.key} at $size px broke the heading/content split',
      );
    }
  });

  test('the slots the shell header and the badge use are headings', () {
    // The shell title (app_shell.dart) and the notification count
    // (notifications_button.dart) are headings, so they read in Cinzel.
    expect(textTheme.titleLarge?.fontFamily, AppTextStyles.cinzelFont);
    expect(textTheme.headlineSmall?.fontFamily, AppTextStyles.cinzelFont);
  });
}
