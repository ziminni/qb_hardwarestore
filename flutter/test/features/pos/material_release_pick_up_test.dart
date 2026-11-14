// Phase 9 F2 (decision 21 §2/§4): a release is a SALE, so it says WHERE the
// stock came from. "Pick up: 3 PC at Store, 2 PC at Bodega" is read from the
// server's deduction rows, and the release receipt is the only place the clerk
// can see it — step 2 is the PLAN, before anything moved.
//
// A release recorded before Phase 9 carries no `pick_up`: the receipt then
// prints no caption rather than inventing a shelf.

import 'package:client/data/models/pick_up.dart';
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

class _StubRequisitions extends RequisitionRepository {
  _StubRequisitions({required this.releaseItems});

  final List<ReleasedLine> releaseItems;

  @override
  Future<TokenVerification> verifyToken(String token) async {
    return TokenVerification(
      token: token,
      requisitionId: 3,
      reqNumber: 'REQ-20261114-0003',
      project: '2-Storey House - Mandaue',
      customer: 'Dela Cruz Construction',
      items: const [
        VerifiedRequisitionItem(
          id: 1,
          variantId: 7,
          variantName: '40kg',
          quantity: 10,
          remaining: 10,
          availability: LineAvailability.full,
          releasable: 10,
        ),
      ],
    );
  }

  @override
  Future<ReleaseResult> release(String token) async {
    return ReleaseResult(
      transactionId: 42,
      transactionNo: 'TXN-20261114-0042',
      status: ReleaseStatus.released,
      items: releaseItems,
      grandTotal: 2700,
      ledgerId: 9,
      balanceDue: 2700,
    );
  }
}

Future<void> _pumpAndRelease(
  WidgetTester tester,
  List<ReleasedLine> items,
) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final viewmodel = MaterialReleaseViewmodel(
    repository: _StubRequisitions(releaseItems: items),
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(home: MaterialReleasePage(viewmodel: viewmodel)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, 'TOKEN-1');
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Release materials'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the release receipt names every shelf the line left', (
    tester,
  ) async {
    await _pumpAndRelease(tester, const [
      ReleasedLine(
        code: 'CEM-40KG',
        releasedNow: 5,
        outstanding: 0,
        pickUp: [
          PickUpPart(locationId: 1, locationName: 'Store', qty: 3, unit: 'PC'),
          PickUpPart(locationId: 2, locationName: 'Bodega', qty: 2, unit: 'PC'),
        ],
      ),
    ]);

    expect(
      find.text('Pick up: 3 PC at Store, 2 PC at Bodega'),
      findsOneWidget,
      reason: 'the clerk must know which shelves this release emptied',
    );
  });

  testWidgets('a line that moved nothing prints no pick-up caption', (
    tester,
  ) async {
    await _pumpAndRelease(tester, const [
      ReleasedLine(
        code: 'CEM-40KG',
        releasedNow: 0,
        outstanding: 5,
        pickUp: [
          PickUpPart(locationId: 1, locationName: 'Store', qty: 3, unit: 'PC'),
        ],
      ),
    ]);

    expect(find.textContaining('Pick up'), findsNothing);
  });

  test('a release answer decodes its pick_up list', () {
    final result = ReleaseResult.fromJson(const {
      'transaction_id': 42,
      'transaction_no': 'TXN-20261114-0042',
      'status': 'RELEASED',
      'items': [
        {
          'code': 'CEM-40KG',
          'released_now': '5.00',
          'outstanding': '0.00',
          'pick_up': [
            {
              'location': 1,
              'location_name': 'Store',
              'qty': '3.00',
              'unit': 'PC',
            },
            {
              'location': 2,
              'location_name': 'Bodega',
              'qty': '2.00',
              'unit': 'PC',
            },
          ],
        },
      ],
      'grand_total': '2700.00',
      'ledger_id': 9,
      'balance_due': '2700.00',
    });

    expect(result.items.single.pickUp, hasLength(2));
    expect(
      result.items.single.pickUpLine,
      'Pick up: 3 PC at Store, 2 PC at Bodega',
    );
  });

  test('a release from a pre-Phase-9 server decodes to no parts', () {
    final result = ReleaseResult.fromJson(const {
      'transaction_id': 42,
      'transaction_no': 'TXN-20261114-0042',
      'status': 'RELEASED',
      'items': [
        {'code': 'CEM-40KG', 'released_now': '5.00', 'outstanding': '0.00'},
      ],
      'grand_total': '2700.00',
      'ledger_id': 9,
      'balance_due': '2700.00',
    });

    expect(result.items.single.pickUp, isEmpty);
    expect(result.items.single.pickUpLine, isNull);
  });
}
