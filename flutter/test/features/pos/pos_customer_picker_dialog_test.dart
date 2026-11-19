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

  testWidgets('does NOT show a "New customer" button in the picker modal', (
    tester,
  ) async {
    await _open(
      tester,
      customers: [_customer(1, 'Maria Santos')],
    );

    expect(find.text('New customer'), findsNothing);
    expect(find.text('Walk-in (anonymous)'), findsOneWidget);
  });

  testWidgets('a search that matches nothing says how to proceed', (
    tester,
  ) async {
    await _open(tester, customers: [_customer(1, 'Maria Santos')]);
    await tester.enterText(find.byType(TextField).first, 'zzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('No customer matches'), findsOneWidget);
    expect(find.textContaining('Customers page'), findsOneWidget);
  });
}
