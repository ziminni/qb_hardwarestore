import 'package:client/core/constants/app_text_styles.dart';
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
}
