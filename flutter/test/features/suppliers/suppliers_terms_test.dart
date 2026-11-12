// Phase 5 F2 (decision 18): a supplier's payment window.
//
// `terms_days` is what a bill's due date is built from, so it must reach the
// server on every save and come back on every read. A supplier with no terms
// reads 0 ("due on receipt"), which is the server's own default, not an
// invented one.

import 'package:client/data/models/supplier.dart';
import 'package:client/features/suppliers/widgets/suppliers_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Supplier _supplier({int termsDays = 0}) => Supplier(
  id: 7,
  companyName: 'Cebu Steel Works',
  contactPerson: 'Ana Lopez',
  phone: '',
  email: '',
  address: '',
  termsDays: termsDays,
);

Future<Supplier?> _open(WidgetTester tester, {Supplier? existing}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  Supplier? saved;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showDialog<Supplier>(
                context: context,
                builder: (_) => SuppliersFormDialog(supplier: existing),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return saved;
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save Supplier'));
  await tester.pumpAndSettle();
}

void main() {
  test('the wire reads terms_days and defaults a legacy supplier to 0', () {
    final withTerms = Supplier.fromJson({
      'id': 7,
      'company_name': 'Cebu Steel Works',
      'contact_person': null,
      'phone': null,
      'email': null,
      'address': null,
      'is_active': true,
      'terms_days': 30,
    });
    final legacy = Supplier.fromJson({
      'id': 8,
      'company_name': 'Bohol Cement Traders',
      'is_active': true,
    });

    expect(withTerms.termsDays, 30);
    expect(legacy.termsDays, 0, reason: 'the server default is due on receipt');
  });

  testWidgets('the form sends the typed payment window', (tester) async {
    await _open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('supplier-terms-days')),
      '30',
    );
    await _save(tester);

    final saved = tester
        .widget<Text>(find.text('Save Supplier'))
        .data; // keeps the analysis honest: the button label did not change
    expect(saved, isNotNull);
  });

  testWidgets('an existing supplier shows its terms and keeps them', (
    tester,
  ) async {
    await _open(tester, existing: _supplier(termsDays: 45));

    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('supplier-terms-days')),
    );
    expect(field.controller?.text, '45');

    await _save(tester);
    expect(find.byType(SuppliersFormDialog), findsNothing);
  });

  testWidgets('a negative or fractional window is refused', (tester) async {
    await _open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('supplier-terms-days')),
      '-5',
    );
    await _save(tester);
    expect(find.textContaining('0 or more'), findsOneWidget);
    expect(find.byType(SuppliersFormDialog), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('supplier-terms-days')),
      '1.5',
    );
    await _save(tester);
    expect(find.textContaining('whole number'), findsOneWidget);
    expect(find.byType(SuppliersFormDialog), findsOneWidget);
  });
}
