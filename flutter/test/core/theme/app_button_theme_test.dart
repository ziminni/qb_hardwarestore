import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/theme/app_button_theme.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every button label in the app uses the brand body font. TextButton used to
/// declare a weight without a family, which silently dropped its label to the
/// platform font while Filled and Outlined buttons rendered in Open Sans.
void main() {
  Future<TextStyle> labelStyleOf(
    WidgetTester tester,
    Widget button,
    String label,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: Center(child: button)),
      ),
    );
    await tester.pumpAndSettle();
    // The button installs its resolved label style as the nearest
    // DefaultTextStyle, so this is what the label actually renders with.
    return DefaultTextStyle.of(tester.element(find.text(label))).style;
  }

  testWidgets('a TextButton label uses the brand body font', (tester) async {
    final style = await labelStyleOf(
      tester,
      TextButton(onPressed: () {}, child: const Text('Retry')),
      'Retry',
    );

    expect(style.fontFamily, AppTextStyles.outfitFont);
    expect(style.fontWeight, FontWeight.w600);
  });

  testWidgets('all three button styles agree on the label font', (
    tester,
  ) async {
    final text = await labelStyleOf(
      tester,
      TextButton(onPressed: () {}, child: const Text('Retry')),
      'Retry',
    );
    final outlined = await labelStyleOf(
      tester,
      OutlinedButton(onPressed: () {}, child: const Text('Retry')),
      'Retry',
    );
    final filled = await labelStyleOf(
      tester,
      FilledButton(onPressed: () {}, child: const Text('Retry')),
      'Retry',
    );

    expect(text.fontFamily, outlined.fontFamily);
    expect(text.fontFamily, filled.fontFamily);
  });

  /// Keyboard focus on the gold buttons must be visible, not just a faint
  /// overlay tint. Focused draws a 2px black side; hover-only stays borderless.
  group('button focus outline', () {
    bool isVisible(BorderSide? side) =>
        side != null && side.style != BorderStyle.none && side.width > 0;

    BorderSide? sideFor(ButtonStyle style, Set<WidgetState> states) =>
        style.side?.resolve(states);

    final styles = <String, ButtonStyle>{
      'filledButton': AppButtonTheme.filledButton().style!,
      'elevatedButton': AppButtonTheme.elevatedButton().style!,
      'textButton': AppButtonTheme.textButton().style!,
    };

    styles.forEach((name, style) {
      test('$name draws a 2px brandBlack side when focused', () {
        final side = sideFor(style, {WidgetState.focused});

        expect(side, isNotNull, reason: '$name has no side for focused');
        expect(side!.color, AppColors.brandBlack);
        expect(side.width, greaterThanOrEqualTo(2));
      });

      test('$name has no visible side when idle', () {
        expect(isVisible(sideFor(style, {})), isFalse);
      });

      test('$name has no visible side when hovered', () {
        expect(isVisible(sideFor(style, {WidgetState.hovered})), isFalse);
      });

      test('$name has no visible side when disabled', () {
        expect(isVisible(sideFor(style, {WidgetState.disabled})), isFalse);
      });
    });
  });
}
