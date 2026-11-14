import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One error-with-retry style for the whole app (LiveLoadErrorBanner plus the
/// hand-built red boxes are replaced by this later).
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in const [Size(1440, 900), Size(760, 900)]) {
    final width = size.width.toInt();

    testWidgets('shows the message on the error tint at $width px', (
      tester,
    ) async {
      await pumpAt(
        tester,
        size,
        const ErrorBanner(message: 'Sales could not be loaded.'),
      );

      final message = find.text('Sales could not be loaded.');
      expect(message, findsOneWidget);
      expect(tester.widget<Text>(message).style?.color, AppColors.errorText);

      final container = tester.widget<Container>(
        find.ancestor(of: message, matching: find.byType(Container)).first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, AppColors.errorTint);
      expect(tester.takeException(), isNull);
    });

    testWidgets('retries when Retry is tapped at $width px', (tester) async {
      var retries = 0;
      await pumpAt(
        tester,
        size,
        ErrorBanner(
          message: 'Sales could not be loaded.',
          onRetry: () => retries++,
        ),
      );

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('has no Retry button when no retry is given', (tester) async {
    await pumpAt(
      tester,
      const Size(1440, 900),
      const ErrorBanner(message: 'Sales could not be loaded.'),
    );

    expect(find.text('Retry'), findsNothing);
  });
}
