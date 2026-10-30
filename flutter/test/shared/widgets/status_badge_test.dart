import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every tone renders its words plus its ruled colors. Color alone is never the
/// message, so each case also asserts the label is on screen.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // D-ruled pairs: success, warning and error come from AppColors; info and
  // neutral are the values fixed in the F3 brief.
  const cases = <(StatusTone, Color, Color, bool)>[
    (StatusTone.success, AppColors.successText, AppColors.successTint, false),
    (StatusTone.warning, AppColors.warningText, AppColors.warningTint, false),
    (StatusTone.error, AppColors.errorText, AppColors.errorTint, false),
    (StatusTone.info, Color(0xFF6E5A22), Color(0xFFF1E6C9), false),
    (StatusTone.neutral, Color(0xFF686257), Color(0xFFF8F6F0), true),
  ];

  for (final size in const [Size(1440, 900), Size(760, 900)]) {
    final width = size.width.toInt();

    testWidgets('each tone renders its label and ruled colors at $width px', (
      tester,
    ) async {
      await pumpAt(
        tester,
        size,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in cases)
              Padding(
                padding: const EdgeInsets.all(4),
                child: StatusBadge(
                  label: 'Badge ${entry.$1.name}',
                  tone: entry.$1,
                ),
              ),
          ],
        ),
      );

      for (final entry in cases) {
        final label = find.text('Badge ${entry.$1.name}');
        expect(label, findsOneWidget);

        final text = tester.widget<Text>(label);
        expect(
          text.style?.color,
          entry.$2,
          reason: 'text color of ${entry.$1.name}',
        );

        final container = tester.widget<Container>(
          find.ancestor(of: label, matching: find.byType(Container)).first,
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, entry.$3, reason: 'tint of ${entry.$1.name}');
        expect(decoration.borderRadius, BorderRadius.circular(999));

        if (entry.$4) {
          final border = decoration.border! as Border;
          expect(border.top.color, AppColors.border);
        } else {
          expect(decoration.border, isNull);
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('defaults to the neutral tone', (tester) async {
    await pumpAt(
      tester,
      const Size(1440, 900),
      const StatusBadge(label: 'Draft status'),
    );

    expect(
      tester.widget<Text>(find.text('Draft status')).style?.color,
      const Color(0xFF686257),
    );
  });
}
