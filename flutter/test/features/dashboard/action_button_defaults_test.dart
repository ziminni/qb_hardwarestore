// Phase 3 Task 0 (U) — buttons that LOOK live but are wired to nothing.
//
// `AdminActionButton`, `InventoryActionButton` and `AdminUserActionButton` each
// defaulted `onPressed` to `?? () {}`, and the three `*Section` widgets did the
// same with `onAction`. A caller who passed no callback still got an ENABLED
// button: it lit up on hover, swallowed the press, and did nothing. That is
// exactly how the dead controls in the 2026-10-24 report survived review.
//
// The rule now: no callback → pass null → Flutter renders the button disabled.
// A disabled button that says nothing is honest; a live-looking one that does
// nothing is not.

import 'package:client/features/admin/widgets/admin_user_action_button.dart';
import 'package:client/features/admin/widgets/admin_user_section.dart';
import 'package:client/features/dashboard/widget/admin_action_button.dart';
import 'package:client/features/dashboard/widget/admin_section.dart';
import 'package:client/features/dashboard/widget/inventory_action_button.dart';
import 'package:client/features/dashboard/widget/inventory_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

bool _outlinedEnabled(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.byType(OutlinedButton)).enabled;

bool _textButtonEnabled(WidgetTester tester) =>
    tester.widget<TextButton>(find.byType(TextButton)).enabled;

void main() {
  group('action buttons without a callback render disabled', () {
    testWidgets('AdminActionButton', (tester) async {
      await _pump(tester, const AdminActionButton(label: 'Nothing'));
      expect(_outlinedEnabled(tester), isFalse);
    });

    testWidgets('InventoryActionButton', (tester) async {
      await _pump(tester, const InventoryActionButton(label: 'Nothing'));
      expect(_outlinedEnabled(tester), isFalse);
    });

    testWidgets('AdminUserActionButton', (tester) async {
      await _pump(tester, const AdminUserActionButton(label: 'Nothing'));
      expect(_outlinedEnabled(tester), isFalse);
    });
  });

  group('action buttons with a callback stay live', () {
    testWidgets('AdminActionButton', (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        AdminActionButton(label: 'Create user', onPressed: () => pressed++),
      );

      await tester.tap(find.text('Create user'));

      expect(pressed, 1);
      expect(_outlinedEnabled(tester), isTrue);
    });

    testWidgets('InventoryActionButton', (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        InventoryActionButton(label: 'Add product', onPressed: () => pressed++),
      );

      await tester.tap(find.text('Add product'));

      expect(pressed, 1);
    });

    testWidgets('AdminUserActionButton', (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        AdminUserActionButton(
          label: 'Create account',
          onPressed: () => pressed++,
        ),
      );

      await tester.tap(find.text('Create account'));

      expect(pressed, 1);
    });
  });

  group('section header actions pass null through', () {
    final sections =
        <String, Widget Function({String? label, VoidCallback? on})>{
          'AdminSection': ({String? label, VoidCallback? on}) => AdminSection(
            title: 'Recent activity',
            actionLabel: label,
            onAction: on,
            child: const Text('body'),
          ),
          'InventorySection': ({String? label, VoidCallback? on}) =>
              InventorySection(
                title: 'Inventory table',
                actionLabel: label,
                onAction: on,
                child: const Text('body'),
              ),
          'AdminUserSection': ({String? label, VoidCallback? on}) =>
              AdminUserSection(
                title: 'User accounts',
                actionLabel: label,
                onAction: on,
                child: const Text('body'),
              ),
        };

    for (final entry in sections.entries) {
      testWidgets('${entry.key} with no onAction renders disabled', (
        tester,
      ) async {
        await _pump(tester, entry.value(label: 'View all'));

        expect(_textButtonEnabled(tester), isFalse);
      });

      testWidgets('${entry.key} with an onAction fires it', (tester) async {
        var pressed = 0;
        await _pump(
          tester,
          entry.value(label: 'View all', on: () => pressed++),
        );

        await tester.tap(find.text('View all'));

        expect(pressed, 1);
        expect(_textButtonEnabled(tester), isTrue);
      });
    }
  });
}
