// Phase 4 Task F4 (decision 18): the payment dialog's discount section, and the
// approval step a discount above the Admin's cap must pass.
//
// Three behaviours are load-bearing:
//   * the cashier sees gross, discount and NET before committing, and the amount
//     received follows the net;
//   * a reason is required as soon as a discount is entered, because the server
//     refuses a reasonless one with DISCOUNT_REASON_REQUIRED;
//   * a discount over the cap does NOT submit: it opens the manager approval dialog,
//     whose password is obscured and never kept, and only a token comes back.

import 'package:client/data/services/discount_approval_service.dart';
import 'package:client/features/pos/widgets/pos_discount_approval_dialog.dart';
import 'package:client/features/pos/widgets/pos_payment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApprovalService extends DiscountApprovalService {
  _FakeApprovalService({this.token = 'TOKEN-1', this.failure});

  final String token;
  final DiscountApprovalException? failure;
  int calls = 0;
  double lastPercent = 0;
  String lastReason = '';

  @override
  Future<DiscountApproval> request({
    required String username,
    required String password,
    required double percent,
    required String reason,
  }) async {
    calls++;
    lastPercent = percent;
    lastReason = reason;
    final boom = failure;
    if (boom != null) throw boom;
    return DiscountApproval(
      token: token,
      percent: percent,
      approver: 'Store Manager',
    );
  }
}

Future<PosPaymentDetails?> _open(
  WidgetTester tester, {
  double total = 1000,
  double cap = 10,
  _FakeApprovalService? approval,
}) async {
  PosPaymentDetails? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showDialog<PosPaymentDetails>(
                context: context,
                builder: (_) => PosPaymentDialog(
                  total: total,
                  discountCapPercent: cap,
                  approvalService: approval,
                ),
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
  return result;
}

Future<void> _enterDiscount(
  WidgetTester tester, {
  required String value,
  String reason = 'bulk order',
}) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Discount amount'),
    value,
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Reason for the discount'),
    reason,
  );
  await tester.pump();
}

void main() {
  testWidgets('a peso discount shows the net as the amount due', (
    tester,
  ) async {
    await _open(tester);
    await _enterDiscount(tester, value: '100');

    expect(find.text('Discount'), findsOneWidget);
    expect(find.text('-₱100.00'), findsOneWidget);
    expect(find.text('Amount due: ₱900.00'), findsOneWidget);
    // The received field follows the net while the cashier has not typed in it.
    final amountField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Amount'),
    );
    expect(amountField.controller?.text, '900.00');
  });

  testWidgets('a percent discount computes off the gross', (tester) async {
    await _open(tester, total: 250.50);
    await tester.tap(find.text('% Percent'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Discount percent'),
      '10',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Reason for the discount'),
      'loyal customer',
    );
    await tester.pump();

    expect(find.text('Amount due: ₱225.45'), findsOneWidget);
  });

  testWidgets('a discount with no reason is refused before submitting', (
    tester,
  ) async {
    await _open(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Discount amount'),
      '100',
    );
    await tester.pump();

    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    expect(find.text('A discount needs a reason'), findsOneWidget);
    // The dialog is still open: nothing was handed back to the page.
    expect(find.text('Payment'), findsOneWidget);
  });

  testWidgets('a discount below the cap submits without approval', (
    tester,
  ) async {
    final approval = _FakeApprovalService();
    await _open(tester, cap: 10, approval: approval);
    await _enterDiscount(tester, value: '50');

    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    expect(approval.calls, 0);
    expect(find.text('Manager approval needed'), findsNothing);
    expect(find.text('Payment'), findsNothing, reason: 'the dialog closed');
  });

  testWidgets('a discount over the cap says so and asks for approval', (
    tester,
  ) async {
    final approval = _FakeApprovalService();
    await _open(tester, cap: 10, approval: approval);
    await _enterDiscount(tester, value: '150');

    expect(find.textContaining('Needs manager approval'), findsOneWidget);

    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    expect(find.text('Manager approval needed'), findsOneWidget);
  });

  testWidgets('the approval dialog obscures the password and holds no copy', (
    tester,
  ) async {
    final approval = _FakeApprovalService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosDiscountApprovalDialog(
            percent: 15,
            reason: 'bulk order',
            service: approval,
          ),
        ),
      ),
    );

    // TextFormField has no obscureText getter: the setting lives on the TextField
    // it builds, which is what the password is actually typed into.
    final password = tester.widget<TextField>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Password'),
        matching: find.byType(TextField),
      ),
    );
    expect(password.obscureText, isTrue);
    expect(password.enableSuggestions, isFalse);
    expect(password.autocorrect, isFalse);
  });

  testWidgets('an approved over-cap discount returns the token, and the sale '
      'carries it', (tester) async {
    final approval = _FakeApprovalService(token: 'APPROVED-TOKEN');
    PosPaymentDetails? details;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                details = await showDialog<PosPaymentDetails>(
                  context: context,
                  builder: (_) => PosPaymentDialog(
                    total: 1000,
                    discountCapPercent: 10,
                    approvalService: approval,
                  ),
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
    await _enterDiscount(tester, value: '150');
    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Approver username'),
      'manager',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'correct horse',
    );
    await tester.tap(find.text('Approve discount'));
    await tester.pumpAndSettle();

    expect(approval.calls, 1);
    expect(approval.lastPercent, closeTo(15, 0.01));
    expect(approval.lastReason, 'bulk order');
    expect(details, isNotNull);
    expect(details!.discountApprovalToken, 'APPROVED-TOKEN');
    expect(details!.discount?.value, 150);
    expect(details!.tenders, hasLength(1));
    // 1,000 gross less the 150 discount: the tender follows the NET.
    expect(details!.amountPaid, 850);
  });

  testWidgets('a refused approval keeps the dialog open with the reason', (
    tester,
  ) async {
    final approval = _FakeApprovalService(
      failure: const DiscountApprovalException(
        'Those credentials cannot approve a discount. Ask a Store Manager or '
        'Admin to approve it with their own username and password.',
      ),
    );
    PosPaymentDetails? details;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                details = await showDialog<PosPaymentDetails>(
                  context: context,
                  builder: (_) => PosPaymentDialog(
                    total: 1000,
                    discountCapPercent: 10,
                    approvalService: approval,
                  ),
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
    await _enterDiscount(tester, value: '150');
    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Approver username'),
      'cashier',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'wrong',
    );
    await tester.tap(find.text('Approve discount'));
    await tester.pumpAndSettle();

    expect(find.textContaining('cannot approve a discount'), findsOneWidget);
    expect(details, isNull, reason: 'nothing submitted without an approval');
  });

  testWidgets(
    'a short tender warns about utang against the NET, not the gross',
    (tester) async {
      await _open(tester, total: 1000);
      await _enterDiscount(tester, value: '100');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '500',
      );
      await tester.pump();

      expect(
        find.textContaining('₱400.00 will be left unpaid'),
        findsOneWidget,
      );
    },
  );
}
