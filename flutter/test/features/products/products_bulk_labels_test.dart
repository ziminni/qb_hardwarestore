// Phase 6 Task 6 (decision 14): the bulk "Print labels" entry point.
//
// Honest note: the button was wired in the same commit as this file, so this test
// LOCKS the behaviour rather than driving it (same deviation as
// products_page_load_test.dart). It exists because the wiring is a bare callback —
// nothing else would fail if it were dropped during a refactor.

import 'package:client/features/products/widgets/products_bulk_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the selection toolbar offers labels, archive and clear', (
    tester,
  ) async {
    var labels = 0;
    var archived = 0;
    var cleared = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductsBulkActions(
            selectedCount: 3,
            onArchive: () => archived++,
            onPrintLabels: () => labels++,
            onClear: () => cleared++,
          ),
        ),
      ),
    );

    expect(find.text('3 selected'), findsOneWidget);

    await tester.tap(find.text('Print labels'));
    expect(labels, 1);
    expect(archived, 0, reason: 'printing labels must not archive anything');

    await tester.tap(find.text('Move to archive'));
    expect(archived, 1);

    await tester.tap(find.text('Clear selection'));
    expect(cleared, 1);
  });
}
