// The release screen as one page (2026-11-27 design, layout B): the waiting
// requests on the left, the chosen request on the right, a Give now stepper on
// every line that can go, and a summary of today's release before the press.

import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:client/features/pos/views/material_release_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _cement = VerifiedRequisitionItem(
  id: 1,
  variantId: 7,
  variantName: 'Portland Cement 40kg',
  quantity: 10,
  remaining: 7,
  availability: LineAvailability.short,
  releasable: 4,
  unit: 'BAG',
  unitPrice: 260,
);

const _wire = VerifiedRequisitionItem(
  id: 2,
  variantId: 8,
  variantName: 'Tie wire #16',
  quantity: 12.5,
  remaining: 12.5,
  availability: LineAvailability.full,
  releasable: 12.5,
  unit: 'KG',
  isWhole: false,
  unitPrice: 40,
);

const _adhesive = VerifiedRequisitionItem(
  id: 3,
  variantId: 9,
  variantName: 'Tile Adhesive',
  quantity: 5,
  remaining: 5,
  availability: LineAvailability.unavailable,
  releasable: 0,
  unit: 'BAG',
  available: false,
  declineReason: 'Discontinued item',
);

const _nails = VerifiedRequisitionItem(
  id: 4,
  variantId: 10,
  variantName: 'Common nails 4"',
  quantity: 2,
  remaining: 0,
  availability: LineAvailability.done,
  releasable: 0,
  unit: 'KG',
);

const _sand = VerifiedRequisitionItem(
  id: 5,
  variantId: 11,
  variantName: 'Washed sand',
  quantity: 3,
  remaining: 3,
  availability: LineAvailability.unavailable,
  releasable: 0,
  unit: 'CU.M',
);

class _Repo extends RequisitionRepository {
  Map<int, double>? sent;

  @override
  Future<List<Requisition>> fetchReleaseQueue() async => const [
    Requisition(
      id: 6,
      reqNumber: 'REQ-0006',
      rawStatus: 'PARTIAL',
      projectName: 'Villanueva residence',
      projectCustomerName: 'Dela Cruz Construction',
      requestedByName: 'Foreman',
      items: [],
    ),
    Requisition(
      id: 9,
      reqNumber: 'REQ-0009',
      rawStatus: 'ACCEPTED',
      projectName: 'Mandaue warehouse',
      projectCustomerName: 'Lim Builders',
      requestedByName: 'Foreman',
      items: [],
    ),
  ];

  @override
  Future<TokenVerification> verifyRequest(int id) async => TokenVerification(
    token: 'tok-6',
    requisitionId: 6,
    reqNumber: 'REQ-0006',
    project: 'Villanueva residence',
    customer: 'Dela Cruz Construction',
    status: 'PARTIAL',
    items: const [_cement, _wire, _adhesive, _nails, _sand],
  );

  @override
  Future<TokenVerification> verifyToken(String token) => verifyRequest(6);

  @override
  Future<ReleaseResult> release(
    String token, {
    Map<int, double>? quantities,
  }) async {
    sent = quantities;
    return const ReleaseResult(
      transactionId: 77,
      transactionNo: 'TXN-20261127-0077',
      status: ReleaseStatus.partial,
      items: [],
      grandTotal: 1280,
      ledgerId: 3,
      balanceDue: 1280,
    );
  }
}

Future<_Repo> _open(WidgetTester tester, {Size size = const Size(1400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final repo = _Repo();
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        home: MaterialReleasePage(
          viewmodel: MaterialReleaseViewmodel(repository: repo),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('REQ-0006').first);
  await tester.pumpAndSettle();
  return repo;
}

String _summary(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(const ValueKey('release-summary')),
      matching: find.byType(Text),
    ),
  ))
    text.data ?? text.textSpan?.toPlainText() ?? '',
].join('\n');

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a wide window shows the queue beside the request', (tester) async {
    await _open(tester);

    final queue = tester.getRect(find.byKey(const ValueKey('release-queue-pane')));
    final request = tester.getRect(
      find.byKey(const ValueKey('release-request-pane')),
    );
    expect(queue.right <= request.left, isTrue, reason: '$queue vs $request');
    expect((queue.top - request.top).abs() < 1, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a narrow window stacks the queue above the request', (
    tester,
  ) async {
    await _open(tester, size: const Size(900, 900));

    final queue = tester.getRect(find.byKey(const ValueKey('release-queue-pane')));
    final request = tester.getRect(
      find.byKey(const ValueKey('release-request-pane')),
    );
    expect(queue.bottom <= request.top, isTrue, reason: '$queue vs $request');
    expect(tester.takeException(), isNull);
  });

  testWidgets('each line says what was given, what is owed and what goes now', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('3 of 10 BAG given'), findsOneWidget);
    expect(find.text('7 still to give · up to 4 can go out now'), findsOneWidget);
    expect(find.text('Short: up to 4 now'), findsOneWidget);
    expect(find.text('Enough stock'), findsOneWidget);
    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('Discontinued item'), findsOneWidget);
    expect(find.text('Already given'), findsOneWidget);
    expect(find.text('Out of stock'), findsOneWidget);
    expect(find.text('Partly released'), findsWidgets);
  });

  testWidgets('minus lowers Give now and the summary follows', (tester) async {
    await _open(tester);

    await _tapKey(tester, 'give-now-minus-1');

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('give-now-1')),
    );
    expect(field.controller!.text, '3');
    expect(find.text('changed from 4'), findsOneWidget);
    final summary = _summary(tester);
    expect(summary, contains('Giving today: 3 BAG Portland Cement 40kg'));
    expect(summary, contains('12.5 KG Tie wire #16'));
    expect(summary, contains('Still open after this:'));
    expect(summary, contains('4 BAG Portland Cement 40kg'));
    expect(find.text('Release 2 items'), findsOneWidget);
  });

  testWidgets('typing an amount sets Give now', (tester) async {
    await _open(tester);

    await tester.enterText(find.byKey(const ValueKey('give-now-2')), '5');
    await tester.pumpAndSettle();

    expect(_summary(tester), contains('5 KG Tie wire #16'));
    expect(find.text('changed from 12.5'), findsOneWidget);
  });

  testWidgets('all amounts at 0 disables the release and says why', (
    tester,
  ) async {
    final repo = await _open(tester);

    for (var i = 0; i < 4; i++) {
      await _tapKey(tester, 'give-now-minus-1');
    }
    await tester.enterText(find.byKey(const ValueKey('give-now-2')), '0');
    await tester.pumpAndSettle();

    final button = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('release-confirm')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Set at least one Give now above 0.'), findsOneWidget);
    expect(repo.sent, isNull);
  });

  testWidgets('after the release the receipt takes the right pane', (
    tester,
  ) async {
    final repo = await _open(tester);
    await _tapKey(tester, 'give-now-minus-1');

    await _tapKey(tester, 'release-confirm');

    expect(repo.sent, {1: 3.0, 2: 12.5});
    expect(find.textContaining('TXN-20261127-0077'), findsWidgets);
    expect(find.byKey(const ValueKey('give-now-1')), findsNothing);
    expect(find.byKey(const ValueKey('release-queue-pane')), findsOneWidget);
    expect(find.text('REQ-0009'), findsOneWidget);
  });
}
