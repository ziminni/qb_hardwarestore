// Task 19: PosCustomerPickerDialog had ZERO tests, and it holds two rules that T6 exists to
// protect:
//
//   1. the Walk-in PLACEHOLDER is not listed as a pickable account - anonymity is offered as its
//      own explicit row, so a cashier cannot select the shared placeholder as if it were a real
//      customer;
//   2. WALK_IN is not offered as a type when RECORDING someone. A named record typed walk-in is
//      refused by the server (WALK_IN_CANNOT_OWE) while `_visible` hides it from this very
//      picker - so it created a customer the cashier could never find and a sale that 400s.
//      That was the dead end task 6 removed, and it was reachable from this dialog.

import 'package:client/data/models/customer.dart';
import 'package:client/features/pos/widgets/pos_customer_picker_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Customer _customer(int id, String name, {String type = 'REGULAR'}) =>
    Customer(id: id, name: name, customerType: type);

/// Pumps the dialog and returns whatever it answers, plus a record of what was created.
Future<
  ({
    PosCustomerSelection? answer,
    List<({String name, CustomerType type})> created,
  })
>
_open(
  WidgetTester tester, {
  List<Customer> customers = const [],
  String? loadError,
  Customer? creates,
  String? createError,
}) async {
  PosCustomerSelection? answer;
  final created = <({String name, CustomerType type})>[];

  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                answer = await showDialog<PosCustomerSelection>(
                  context: context,
                  builder: (_) => PosCustomerPickerDialog(
                    customers: customers,
                    loadError: loadError,
                    onCreate: (name, type) async {
                      created.add((name: name, type: type));
                      return (creates, createError);
                    },
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return (answer: answer, created: created);
}

/// The answer is only assigned once the dialog pops, so the tap and the read must be separated.
Future<PosCustomerSelection?> _tapFor(
  WidgetTester tester,
  String label, {
  List<Customer> customers = const [],
  Customer? creates,
  String? createError,
}) async {
  PosCustomerSelection? answer;
  final created = <({String name, CustomerType type})>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                answer = await showDialog<PosCustomerSelection>(
                  context: context,
                  builder: (_) => PosCustomerPickerDialog(
                    customers: customers,
                    loadError: null,
                    onCreate: (name, type) async {
                      created.add((name: name, type: type));
                      return (creates, createError);
                    },
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
  return answer;
}

void main() {
  testWidgets('lists the named customers to choose from', (tester) async {
    await _open(
      tester,
      customers: [_customer(1, 'Maria Santos'), _customer(2, 'Dela Cruz')],
    );

    expect(find.text('Who is this sale for?'), findsOneWidget);
    expect(find.text('Maria Santos'), findsOneWidget);
    expect(find.text('Dela Cruz'), findsOneWidget);
    expect(find.text('Walk-in (anonymous)'), findsOneWidget);
  });

  testWidgets('does NOT list the Walk-in PLACEHOLDER as a pickable account', (
    tester,
  ) async {
    // It is offered as the explicit anonymous row instead. Listing it twice would let a cashier
    // select the shared placeholder as though it were a real customer.
    await _open(
      tester,
      customers: [
        _customer(1, Customer.walkInName, type: 'WALK_IN'),
        _customer(2, 'Maria Santos'),
      ],
    );

    expect(find.text('Maria Santos'), findsOneWidget);
    expect(
      find.text(Customer.walkInName),
      findsNothing,
      reason:
          'the placeholder is not a real account, and anonymity has its own row',
    );
  });

  testWidgets(
    'choosing "Walk-in (anonymous)" answers the anonymous selection',
    (tester) async {
      final answer = await _tapFor(
        tester,
        'Walk-in (anonymous)',
        customers: [_customer(1, 'Maria Santos')],
      );

      expect(
        answer,
        isNotNull,
        reason: 'anonymous is a CHOICE, not a cancellation',
      );
      expect(answer!.isAnonymous, isTrue);
      expect(answer.customer, isNull);
    },
  );

  testWidgets('choosing a customer answers that customer', (tester) async {
    final answer = await _tapFor(
      tester,
      'Maria Santos',
      customers: [_customer(7, 'Maria Santos')],
    );

    expect(answer, isNotNull);
    expect(answer!.isAnonymous, isFalse);
    expect(answer.customer?.id, 7);
  });

  testWidgets(
    'a cancelled dialog answers nothing, which is DIFFERENT from anonymous',
    (tester) async {
      await _open(tester, customers: [_customer(1, 'Maria Santos')]);
      Navigator.of(tester.element(find.text('Who is this sale for?'))).pop();
      await tester.pumpAndSettle();

      // Null means "change nothing"; the anonymous selection means "go back to anonymous". The
      // wrapper type exists precisely so those two cannot be confused.
      expect(find.text('Who is this sale for?'), findsNothing);
    },
  );

  testWidgets('a failed load is stated, not shown as an empty list', (
    tester,
  ) async {
    await _open(tester, loadError: 'The customer list could not be loaded.');

    expect(find.text('The customer list could not be loaded.'), findsOneWidget);
  });

  group('recording a new customer', () {
    testWidgets(
      'asks only for a name and a type - never a TIN or a credit limit',
      (tester) async {
        await _open(tester);
        await tester.tap(find.text('New customer'));
        await tester.pumpAndSettle();

        expect(find.text('Name'), findsOneWidget);
        expect(find.text('Type'), findsOneWidget);
        expect(find.text('Save and use'), findsOneWidget);
        // Credit control is not the till's job (decision 14, locked decision 1).
        expect(find.textContaining('TIN'), findsNothing);
        expect(find.textContaining('credit'), findsNothing);
      },
    );

    testWidgets('does NOT offer Walk-in as a type for a NAMED record', (
      tester,
    ) async {
      await _open(tester);
      await tester.tap(find.text('New customer'));
      await tester.pumpAndSettle();

      expect(find.text('Regular'), findsOneWidget);
      for (final label in ['Contractor', 'Construction Firm']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(
        find.text('Walk-in'),
        findsNothing,
        reason:
            'a record typed walk-in is refused by the server AND hidden by this picker - '
            'the dead end task 6 removed',
      );
    });

    testWidgets('an empty name is refused WITHOUT calling the server', (
      tester,
    ) async {
      final result = await _open(tester);
      await tester.tap(find.text('New customer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and use'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Enter the customer'), findsOneWidget);
      expect(
        result.created,
        isEmpty,
        reason: 'a blank name must not become a POST',
      );
      expect(
        find.text('Who is this sale for?'),
        findsOneWidget,
        reason: 'the dialog stays open',
      );
    });

    testWidgets('a failed create shows the SERVER message and stays open', (
      tester,
    ) async {
      final result = await _open(
        tester,
        createError: 'A customer with that name already exists.',
      );
      await tester.tap(find.text('New customer'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Maria Santos');
      await tester.tap(find.text('Save and use'));
      await tester.pumpAndSettle();

      expect(
        find.text('A customer with that name already exists.'),
        findsOneWidget,
      );
      // A create that failed must select NOTHING and must not close as though it worked.
      expect(result.answer, isNull);
      expect(result.created.single.name, 'Maria Santos');
    });

    testWidgets(
      'a successful create answers with it, and sends the CHOSEN type',
      (tester) async {
        PosCustomerSelection? answer;
        final created = <({String name, CustomerType type})>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      answer = await showDialog<PosCustomerSelection>(
                        context: context,
                        builder: (_) => PosCustomerPickerDialog(
                          customers: const [],
                          loadError: null,
                          onCreate: (name, type) async {
                            created.add((name: name, type: type));
                            return (_customer(77, name), null);
                          },
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('New customer'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'New Person');
        await tester.tap(find.text('Contractor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save and use'));
        await tester.pumpAndSettle();

        expect(answer?.customer?.name, 'New Person');
        expect(created.single.name, 'New Person');
        expect(
          created.single.type,
          CustomerType.contractor,
          reason:
              'the chip the cashier tapped is what gets sent, not the default',
        );
      },
    );
  });

  testWidgets('a search that matches nothing says how to proceed', (
    tester,
  ) async {
    await _open(tester, customers: [_customer(1, 'Maria Santos')]);
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('No customer matches'), findsOneWidget);
    expect(find.textContaining('New customer'), findsWidgets);
  });
}
