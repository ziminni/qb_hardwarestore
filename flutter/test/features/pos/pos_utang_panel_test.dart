// Task 19 (review finding F5): PosUtangPanel had ZERO tests.
//
// The panel is the till's only statement about what a customer owes, and it encodes two rules
// that were verified only by reading the code:
//   * a FAILED load must not render 0.00 - a zero balance is a CLAIM that the customer owes
//     nothing, and it is the more believable for being a number;
//   * `total_credit_limit == 0` means NOT SET, so warning on it would fire for every customer on
//     every utang sale, and the warning is ADVISORY - it never blocks a sale.
//
// The widget is stateless and driven by explicit values precisely so these can be asserted
// without a server.

import 'package:client/data/models/customer.dart';
import 'package:client/features/pos/widgets/pos_utang_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Customer _customer({double creditLimit = 0}) => Customer(
  id: 6,
  name: 'Maria Santos',
  customerType: 'REGULAR',
  totalCreditLimit: creditLimit,
);

CustomerLedgerSummary _summary({
  double balance = 0,
  int open = 0,
  int overdue = 0,
}) => CustomerLedgerSummary(
  customerId: 6,
  customerName: 'Maria Santos',
  totalBalance: balance,
  openCount: open,
  overdueCount: overdue,
);

Future<void> _pump(
  WidgetTester tester, {
  Customer? customer,
  CustomerLedgerSummary? summary,
  String? error,
  bool isLoading = false,
  double thisSaleTotal = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PosUtangPanel(
          customer: customer,
          summary: summary,
          error: error,
          isLoading: isLoading,
          thisSaleTotal: thisSaleTotal,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('an anonymous sale says WHY there is nothing to show', (
    tester,
  ) async {
    await _pump(tester, customer: null);

    expect(find.textContaining('Anonymous sale'), findsOneWidget);
    expect(find.textContaining('no account to charge'), findsOneWidget);
    // An empty box would leave the cashier wondering whether it failed to load.
    expect(find.text('No utang'), findsNothing);
    expect(find.text('No credit limit set'), findsNothing);
  });

  testWidgets('a load in flight shows progress, not a balance', (tester) async {
    await _pump(tester, customer: _customer(), isLoading: true);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('No utang'), findsNothing);
  });

  testWidgets('a FAILED load shows the error and never 0.00', (tester) async {
    await _pump(
      tester,
      customer: _customer(),
      error: 'Cannot connect to the BuildPro server.',
    );

    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);
    expect(
      find.text('No utang'),
      findsNothing,
      reason:
          '0.00 is a claim that they owe nothing, and it is the more believable for being a number',
    );
    expect(find.textContaining('headroom'), findsNothing);
  });

  testWidgets('a customer who owes money shows the balance and the counts', (
    tester,
  ) async {
    await _pump(
      tester,
      customer: _customer(),
      summary: _summary(balance: 250, open: 1, overdue: 1),
    );

    expect(find.text('₱250.00 outstanding'), findsOneWidget);
    expect(find.text('1 open · 1 overdue'), findsOneWidget);
    expect(find.textContaining('Regular'), findsOneWidget);
  });

  testWidgets('a customer with no debt says so instead of showing 0.00', (
    tester,
  ) async {
    await _pump(tester, customer: _customer(), summary: _summary());

    expect(find.text('No utang'), findsOneWidget);
    expect(find.textContaining('outstanding'), findsNothing);
    // No counts line either - "0 open · 0 overdue" is noise on a customer who owes nothing.
    expect(find.textContaining('overdue'), findsNothing);
  });

  group('the credit-limit rule', () {
    testWidgets(
      '0 means NOT SET, so it is a neutral note and never a warning',
      (tester) async {
        await _pump(
          tester,
          customer: _customer(creditLimit: 0),
          summary: _summary(balance: 900),
          thisSaleTotal: 500,
        );

        expect(find.text('No credit limit set'), findsOneWidget);
        expect(
          find.textContaining('over the'),
          findsNothing,
          reason:
              'warning on 0 would fire for every customer on every utang sale',
        );
      },
    );

    testWidgets('within the limit it shows the remaining headroom', (
      tester,
    ) async {
      await _pump(
        tester,
        customer: _customer(creditLimit: 1000),
        summary: _summary(balance: 200),
        thisSaleTotal: 300,
      );

      expect(find.textContaining('Limit ₱1000.00'), findsOneWidget);
      expect(find.textContaining('₱500.00 headroom'), findsOneWidget);
      expect(find.textContaining('over the'), findsNothing);
    });

    testWidgets(
      'a sale that would exceed the limit warns by the exact overage',
      (tester) async {
        await _pump(
          tester,
          customer: _customer(creditLimit: 1000),
          summary: _summary(balance: 900),
          thisSaleTotal: 250,
        );

        expect(
          find.textContaining(
            'This sale would take them ₱150.00 over the ₱1000.00 limit',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('exactly at the limit is NOT over it', (tester) async {
      // The boundary decides whether a customer is warned at the moment they are still fine.
      await _pump(
        tester,
        customer: _customer(creditLimit: 1000),
        summary: _summary(balance: 700),
        thisSaleTotal: 300,
      );

      expect(find.textContaining('over the'), findsNothing);
      expect(find.textContaining('₱0.00 headroom'), findsOneWidget);
    });

    testWidgets('the warning is ADVISORY: the balance and counts still render', (
      tester,
    ) async {
      // "Never a hard block" is a property of this widget being presentational - it has no
      // callback it could refuse with. Asserted so that adding one has to break a test.
      await _pump(
        tester,
        customer: _customer(creditLimit: 100),
        summary: _summary(balance: 900, open: 2, overdue: 1),
        thisSaleTotal: 500,
      );

      expect(find.text('₱900.00 outstanding'), findsOneWidget);
      expect(find.text('2 open · 1 overdue'), findsOneWidget);
      expect(find.textContaining('over the ₱100.00 limit'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
