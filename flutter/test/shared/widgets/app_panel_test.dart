import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The white panel every page is built from. Checked at a desktop width and a
/// half-window width, because the panel is what every narrow defect showed up
/// in first.
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

    testWidgets('renders its child on the white bordered panel at $width px', (
      tester,
    ) async {
      await pumpAt(tester, size, const AppPanel(child: Text('Panel body')));

      expect(find.text('Panel body'), findsOneWidget);

      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: find.byType(AppPanel),
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.color, AppColors.cardBackground);
      expect(decoration.borderRadius, BorderRadius.circular(16));
      final border = decoration.border! as Border;
      expect(border.top.color, AppColors.border);
      expect(border.top.width, 1);

      // The body sits inside the 18 px padding (the 1 px border is painted
      // inside the box, it does not inset the child).
      final panel = tester.getTopLeft(find.byType(AppPanel));
      final body = tester.getTopLeft(find.text('Panel body'));
      expect(body.dx - panel.dx, 18);
      expect(body.dy - panel.dy, 18);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a title and a trailing widget at $width px', (
      tester,
    ) async {
      await pumpAt(
        tester,
        size,
        const AppPanel(
          title: 'Low stock',
          trailing: Text('12 items'),
          child: Text('Panel body'),
        ),
      );

      expect(find.text('Low stock'), findsOneWidget);
      expect(find.text('12 items'), findsOneWidget);
      expect(find.text('Panel body'), findsOneWidget);

      // The title sits above the body, and the trailing widget to its right.
      final title = tester.getBottomLeft(find.text('Low stock'));
      final body = tester.getTopLeft(find.text('Panel body'));
      expect(body.dy, greaterThan(title.dy));
      final trailing = tester.getTopLeft(find.text('12 items'));
      expect(trailing.dx, greaterThan(title.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets('takes the full width it is given at $width px', (
      tester,
    ) async {
      await pumpAt(tester, size, const AppPanel(child: Text('Panel body')));

      expect(tester.getSize(find.byType(AppPanel)).width, size.width);
    });
  }
}
