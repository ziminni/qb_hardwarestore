// Phase 1, Task 9 (decision 05): the shelf can be short, and a short shelf no longer
// refuses the whole release. The till releases what is there, says so per line BEFORE the
// irreversible press, and leaves the rest open on the same token.
//
// What a viewmodel test cannot see lives here: that each line's availability is on screen,
// that the confirm press is gone when nothing can go, and that the receipt says the request
// is still partly open.
import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:client/features/pos/views/material_release_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

VerifiedRequisitionItem _line({
  int id = 1,
  String name = 'Portland Cement 40 kg',
  double quantity = 10,
  double remaining = 10,
  LineAvailability availability = LineAvailability.full,
  double releasable = 10,
  bool? available,
  String declineReason = '',
}) => VerifiedRequisitionItem(
  id: id,
  variantId: id,
  variantName: name,
  quantity: quantity,
  remaining: remaining,
  availability: availability,
  releasable: releasable,
  available: available,
  declineReason: declineReason,
);

TokenVerification _verified(
  List<VerifiedRequisitionItem> items, {
  String token = 'b1e0c4d2-token-0117',
}) => TokenVerification(
  token: token,
  requisitionId: 17,
  reqNumber: 'REQ-20261024-0117',
  project: '2-Storey Residential House - Mandaue City',
  customer: 'Dela Cruz Construction and Supply Corporation',
  items: items,
);

class _StubRequisitions extends RequisitionRepository {
  _StubRequisitions({required this.verifications, this.releaseResult});

  /// One verification per scan, in order: the second scan of the same token sees what the
  /// first one left behind.
  final List<TokenVerification> verifications;
  final ReleaseResult? releaseResult;
  Object? failRelease;
  int verifyCalls = 0;
  final List<String> released = [];

  @override
  Future<TokenVerification> verifyToken(String token) async {
    final index = verifyCalls < verifications.length
        ? verifyCalls
        : verifications.length - 1;
    verifyCalls++;
    return verifications[index];
  }

  @override
  Future<ReleaseResult> release(String token) async {
    if (failRelease case final failure?) throw failure;
    released.add(token);
    return releaseResult ?? _released();
  }
}

ReleaseResult _released({List<ReleasedLine> items = const []}) => ReleaseResult(
  transactionId: 184,
  transactionNo: 'TXN-20261030-0184',
  status: ReleaseStatus.released,
  items: items,
  grandTotal: 2700,
  ledgerId: 41,
  balanceDue: 2700,
);

ReleaseResult _partiallyReleased() => ReleaseResult(
  transactionId: 184,
  transactionNo: 'TXN-20261030-0184',
  status: ReleaseStatus.partial,
  items: const [
    ReleasedLine(code: 'CEM-40', releasedNow: 10, outstanding: 0),
    ReleasedLine(code: 'STL-10', releasedNow: 4, outstanding: 6),
  ],
  grandTotal: 2700,
  ledgerId: 41,
  balanceDue: 2700,
);

/// Four lines in the four states decision 05 puts on screen: one goes out whole, one is
/// short, one is out of stock and one was already taken by an earlier scan.
List<VerifiedRequisitionItem> _mixedLines() => [
  _line(),
  _line(
    id: 2,
    name: 'Deformed Steel Bar 10 mm x 6 m Grade 60',
    availability: LineAvailability.short,
    releasable: 4,
  ),
  _line(
    id: 3,
    name: 'Marine Plywood 3/4 in',
    quantity: 24,
    remaining: 24,
    availability: LineAvailability.unavailable,
    releasable: 0,
  ),
  _line(
    id: 4,
    name: 'PVC Pipe 2 in x 3 m',
    quantity: 6,
    remaining: 0,
    availability: LineAvailability.done,
    releasable: 0,
  ),
];

Future<MaterialReleaseViewmodel> _pump(
  WidgetTester tester,
  RequisitionRepository repository,
) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final viewmodel = MaterialReleaseViewmodel(repository: repository);
  addTearDown(viewmodel.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(home: MaterialReleasePage(viewmodel: viewmodel)),
    ),
  );
  await tester.pumpAndSettle();
  return viewmodel;
}

Future<void> _scan(WidgetTester tester, String token) async {
  await tester.enterText(find.byType(TextField), token);
  // The field enables the button on its next frame.
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
  await tester.pumpAndSettle();
}

Future<void> _pressRelease(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Release materials');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('MaterialReleasePage: a short shelf', () {
    testWidgets('every line says what can leave the store before the press', (
      tester,
    ) async {
      final repo = _StubRequisitions(verifications: [_verified(_mixedLines())]);
      await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');

      expect(find.text('Full'), findsOneWidget);
      expect(find.text('Short'), findsOneWidget);
      expect(
        find.text('4 of 10 available'),
        findsOneWidget,
        reason: 'a short line is only honest with the quantity beside it',
      );
      expect(find.text('Unavailable'), findsOneWidget);
      expect(find.text('Already released'), findsOneWidget);
    });

    testWidgets('the confirm press names what goes now and what stays open', (
      tester,
    ) async {
      final repo = _StubRequisitions(verifications: [_verified(_mixedLines())]);
      await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');

      expect(
        find.text(
          'Releases 2 of 4 lines now. The rest stays open on this token.',
        ),
        findsOneWidget,
        reason:
            'the clerk has to be able to say what the customer is NOT '
            'taking today before pressing the irreversible button',
      );
    });

    // Phase 1b (decisions 10 + 13): the STORE's answer is a different sentence from
    // the shelf's. "Not available" means the line will never be served; "Unavailable"
    // means the shelf is empty today and the project can come back for it.
    testWidgets('a line the store refused says so, and why', (tester) async {
      final repo = _StubRequisitions(
        verifications: [
          _verified([
            _line(),
            _line(
              id: 2,
              name: 'Deformed Steel Bar 16 mm x 6 m Grade 60',
              quantity: 20,
              remaining: 20,
              availability: LineAvailability.unavailable,
              releasable: 0,
              available: false,
              declineReason: 'We do not carry 16 mm rebar',
            ),
          ]),
        ],
      );
      await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');

      expect(
        find.text('Not available'),
        findsOneWidget,
        reason: 'the store refused this line; the shelf was not merely empty',
      );
      expect(
        find.text('Unavailable'),
        findsNothing,
        reason: 'the two words are different instructions to the clerk',
      );
      expect(
        find.text('We do not carry 16 mm rebar'),
        findsOneWidget,
        reason: 'the clerk has to be able to repeat the store\'s reason',
      );
    });

    testWidgets('the confirm summary does not count a refused line', (
      tester,
    ) async {
      final repo = _StubRequisitions(
        verifications: [
          _verified([
            _line(),
            _line(id: 2, availability: LineAvailability.short, releasable: 4),
            _line(
              id: 3,
              quantity: 20,
              remaining: 20,
              availability: LineAvailability.unavailable,
              releasable: 0,
              available: false,
              declineReason: 'We do not carry 16 mm rebar',
            ),
          ]),
        ],
      );
      await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');

      expect(
        find.text(
          'Releases 2 of 2 lines now. The rest stays open on this token.',
        ),
        findsOneWidget,
        reason:
            'the denominator is what the request promises, and the store '
            'promised nothing for the refused line',
      );
    });

    testWidgets('nothing releasable leaves no press and gives the reason', (
      tester,
    ) async {
      final repo = _StubRequisitions(
        verifications: [
          _verified([
            _line(availability: LineAvailability.unavailable, releasable: 0),
            _line(
              id: 2,
              availability: LineAvailability.short,
              quantity: 8,
              remaining: 8,
              releasable: 0,
            ),
          ]),
        ],
      );
      await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');

      expect(
        find.widgetWithText(FilledButton, 'Release materials'),
        findsNothing,
        reason: 'a press that can only fail is not offered at all',
      );
      expect(
        find.textContaining('in stock right now'),
        findsOneWidget,
        reason: 'the clerk is told why, and that the token still works',
      );
      expect(repo.released, isEmpty);
    });

    testWidgets('a token whose lines are all out says the token is finished', (
      tester,
    ) async {
      final repo = _StubRequisitions(
        verifications: [
          _verified([
            _line(
              remaining: 0,
              availability: LineAvailability.done,
              releasable: 0,
            ),
          ]),
        ],
      );
      await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');

      expect(find.textContaining('already released'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Release materials'),
        findsNothing,
      );
    });
  });

  group('MaterialReleasePage: the release answer', () {
    // Decision 13: RELEASED means every AVAILABLE line is out. A Not available line
    // keeps its outstanding quantity in the record forever; printing "still open" would
    // send the project back for goods the store already refused to hand over.
    testWidgets('a refused line left outstanding still reads Released', (
      tester,
    ) async {
      final repo = _StubRequisitions(
        verifications: [
          _verified([
            _line(),
            _line(
              id: 2,
              quantity: 20,
              remaining: 20,
              availability: LineAvailability.unavailable,
              releasable: 0,
              available: false,
              declineReason: 'We do not carry 16 mm rebar',
            ),
          ]),
        ],
        releaseResult: _released(
          items: const [
            ReleasedLine(
              code: 'CEM-40',
              releasedNow: 10,
              outstanding: 0,
              available: true,
            ),
            ReleasedLine(
              code: 'STL-16',
              releasedNow: 0,
              outstanding: 20,
              available: false,
              declineReason: 'We do not carry 16 mm rebar',
            ),
          ],
        ),
      );
      final viewmodel = await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');
      await _pressRelease(tester);

      expect(find.text('Released'), findsOneWidget);
      expect(find.text('Partially released'), findsNothing);
      expect(
        find.textContaining('still open on this token'),
        findsNothing,
        reason: 'a spent token must never promise a return visit',
      );
      expect(viewmodel.result?.openLineCount, 0);
      expect(viewmodel.result?.isPartial, isFalse);
    });

    testWidgets('a partial release says the request is still open', (
      tester,
    ) async {
      final repo = _StubRequisitions(
        verifications: [_verified(_mixedLines())],
        releaseResult: _partiallyReleased(),
      );
      await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');
      await _pressRelease(tester);

      expect(find.text('Partially released'), findsOneWidget);
      expect(
        find.text('Partially released: 1 line still open on this token.'),
        findsOneWidget,
        reason:
            'the clerk has to be able to tell the project what is still owed, '
            'and that they can come back for it',
      );
      expect(find.textContaining('TXN-20261030-0184'), findsWidgets);
      expect(find.text('Released'), findsNothing);
    });

    testWidgets('a full release still reads as released', (tester) async {
      final repo = _StubRequisitions(
        verifications: [
          _verified([
            _line(),
            _line(
              id: 2,
              name: 'PVC Pipe 2 in x 3 m',
              quantity: 6,
              remaining: 6,
              releasable: 6,
            ),
          ]),
        ],
        releaseResult: _released(
          items: const [
            ReleasedLine(code: 'CEM-40', releasedNow: 10, outstanding: 0),
            ReleasedLine(code: 'PVC-2', releasedNow: 6, outstanding: 0),
          ],
        ),
      );
      await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');
      await _pressRelease(tester);

      expect(find.text('Released'), findsOneWidget);
      expect(find.textContaining('still open on this token'), findsNothing);
    });

    // Task 10 (carried from the Task 9 review): that sentence is about a COUNT, so it
    // must not be printed for a zero. The server can answer PARTIAL while every line is
    // finished, and "Partially released: 0 lines still open on this token" reads as a
    // mistake to the clerk, who then tells the project to come back for nothing.
    testWidgets('a partial status with nothing left open says no line count', (
      tester,
    ) async {
      final repo = _StubRequisitions(
        verifications: [_verified(_mixedLines())],
        releaseResult: ReleaseResult(
          transactionId: 184,
          transactionNo: 'TXN-20261030-0184',
          status: ReleaseStatus.partial,
          items: const [
            ReleasedLine(code: 'CEM-40', releasedNow: 10, outstanding: 0),
            ReleasedLine(code: 'STL-10', releasedNow: 6, outstanding: 0),
          ],
          grandTotal: 2700,
          ledgerId: 41,
          balanceDue: 2700,
        ),
      );
      await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');
      await _pressRelease(tester);

      expect(
        find.textContaining('still open on this token'),
        findsNothing,
        reason: 'a count of zero is not a sentence, it is a wrong promise',
      );
      expect(find.textContaining('0 lines'), findsNothing);
    });

    testWidgets('a second scan of the same token shows what the first left', (
      tester,
    ) async {
      final repo = _StubRequisitions(
        verifications: [
          _verified([
            _line(),
            _line(id: 2, availability: LineAvailability.short, releasable: 4),
          ]),
          _verified([
            _line(
              remaining: 0,
              availability: LineAvailability.done,
              releasable: 0,
            ),
            _line(id: 2, availability: LineAvailability.short, releasable: 4),
          ]),
        ],
        releaseResult: _partiallyReleased(),
      );
      await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');
      await _pressRelease(tester);

      await tester.ensureVisible(
        find.widgetWithText(OutlinedButton, 'Verify another token'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Verify another token'),
      );
      await tester.pumpAndSettle();
      // The same token is still in the project's hands after a short release.
      await _scan(tester, 'b1e0c4d2-token-0117');

      expect(repo.verifyCalls, 2);
      expect(find.text('Already released'), findsOneWidget);
      expect(find.text('4 of 10 available'), findsOneWidget);
      expect(
        find.textContaining('TXN-20261030-0184'),
        findsNothing,
        reason: 'the first scan receipt must not sit over the second scan',
      );
      expect(
        find.widgetWithText(FilledButton, 'Release materials'),
        findsOneWidget,
        reason: 'the rest is still collectable on this token',
      );
    });

    testWidgets('a CLOSED request tells the clerk to ask the project', (
      tester,
    ) async {
      final repo = _StubRequisitions(verifications: [_verified(_mixedLines())])
        ..failRelease = const RequisitionServiceException(
          'This request was closed in the project system. '
          'Ask the project to send a new one.',
        );
      await _pump(tester, repo);
      await _scan(tester, 'b1e0c4d2-token-0117');
      await _pressRelease(tester);

      expect(
        find.textContaining('closed in the project system'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Ask the project to send a new one'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Go to Shifts'),
        findsNothing,
        reason: 'a closed request is not fixed at the till',
      );
    });

    // Decision 13 edge case 7: a WAITING or DECLINED token is refused with a coded
    // answer. The till must show the clerk what that code MEANS, not the raw code.
    testWidgets('a WAITING token says a store manager must accept it first', (
      tester,
    ) async {
      await _expectRefusal(
        tester,
        const RequisitionServiceException(
          'The store has not accepted this request yet. A store manager must '
          'accept it under Project requests first.',
          code: 'REQUISITION_WAITING',
        ),
      );
    });

    testWidgets('a DECLINED token says the store refused it', (tester) async {
      await _expectRefusal(
        tester,
        const RequisitionServiceException(
          'The store declined this request, so nothing can be released for it.',
          code: 'REQUISITION_DECLINED',
        ),
      );
    });
  });
}

/// Scans a token whose release is refused, and reads the sentence on screen.
Future<void> _expectRefusal(
  WidgetTester tester,
  RequisitionServiceException failure,
) async {
  final repo = _StubRequisitions(verifications: [_verified(_mixedLines())])
    ..failRelease = failure;
  await _pump(tester, repo);
  await _scan(tester, 'b1e0c4d2-token-0117');
  await _pressRelease(tester);

  expect(find.textContaining(failure.message), findsOneWidget);
  expect(
    find.textContaining('REQUISITION_'),
    findsNothing,
    reason: 'the code is for machines; the clerk reads the sentence',
  );
}
