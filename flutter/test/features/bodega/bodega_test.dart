// Decision 25 (rev. 2026-11-18): the Bodega Checker's phone screens.
//
// Pinned here, at phone size (390 x 844):
//   * the wire shapes parse the server's payloads;
//   * the checker is fenced into `/bodega/`, lands on Pick-ups, and sees no
//     till, catalogue or stock-moving screen;
//   * scanning the receipt QR opens its claim; a release sends what was typed,
//     refuses more than is left before spending a request, and posts once;
//   * a delivery check sends good and damaged per line, shows what is missing,
//     and refuses more than was delivered before spending a request.

import 'dart:async';

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/bodega.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/bodega_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/bodega_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/bodega/viewmodels/bodega_viewmodel.dart';
import 'package:client/features/bodega/views/bodega_pages.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _checkerRole = Role(id: 9, name: 'bodega', displayName: 'Bodega Checker');

Map<String, dynamic> _claimJson({
  double remaining = 4,
  List releases = const [],
}) => {
  'sale': 31,
  'transaction_no': 'TRX-20261117-0007',
  'or_number': 'OR-20261117-0007',
  'customer_name': 'Juan Dela Cruz',
  'sold_at': '2026-11-17T09:00:00+08:00',
  'is_open': remaining > 0,
  'remaining_total': remaining,
  'lines': [
    {
      'variant': 5,
      'label': 'Gravel — 3/4',
      'unit': 'CU.M',
      'location': 2,
      'location_name': 'Bodega',
      'sold': 6.0,
      'released': 6 - remaining,
      'remaining': remaining,
    },
  ],
  'releases': releases,
};

Map<String, dynamic> _releaseJson() => {
  'id': 1,
  'number': 'BR-20261117-0001',
  'sale': 31,
  'transaction_no': 'TRX-20261117-0007',
  'customer_name': 'Juan Dela Cruz',
  'checker_name': 'Bodega Checker',
  'received_by': 'Pedro',
  'plate_no': 'ABC 123',
  'notes': '',
  'created_at': '2026-11-17T10:00:00+08:00',
  'lines': [
    {
      'variant': 5,
      'label': 'Gravel — 3/4',
      'unit': 'CU.M',
      'location': 2,
      'location_name': 'Bodega',
      'qty': '2.00',
    },
  ],
};

Map<String, dynamic> _deliveryJson({String status = 'PENDING'}) => {
  'id': 4,
  'number': 'BD-20261118-0001',
  'receipt': 12,
  'location': 2,
  'location_name': 'Bodega',
  'supplier_name': 'Mactan Aggregates',
  'received_by_name': 'Stock Er',
  'status': status,
  'checked_by_name': status == 'PENDING' ? '' : 'Bodega Checker',
  'checked_at': null,
  'notes': '',
  'created_at': '2026-11-18T08:00:00+08:00',
  'lines': [
    {
      'id': 41,
      'variant': 7,
      'label': 'Hollow Blocks — 4 inch',
      'unit': 'PC',
      'is_whole': true,
      'delivered_qty': '1000.00',
      'good_qty': status == 'PENDING' ? null : '980.00',
      'damaged_qty': status == 'PENDING' ? null : '15.00',
      'missing_qty': status == 'PENDING' ? null : '5.00',
      'remarks': '',
    },
  ],
};

class _FakeBodegaRepository extends BodegaRepository {
  _FakeBodegaRepository() : super(service: BodegaService());

  final releases = <BodegaReleaseRequest>[];
  Completer<void>? hold;
  BodegaClaim claim = BodegaClaim.fromJson(_claimJson());
  List<BodegaDelivery> deliveries = [BodegaDelivery.fromJson(_deliveryJson())];
  final confirmations = <BodegaDeliveryConfirmation>[];

  @override
  Future<List<BodegaStockRow>> fetchStock() async => [
    BodegaStockRow.fromJson(const {
      'variant_id': 5,
      'product_name': 'Gravel',
      'variant_name': '3/4',
      'category': 'Aggregates',
      'unit': 'CU.M',
      'location_id': 2,
      'location_name': 'Bodega',
      'is_home': true,
      'on_hand': 6.0,
      'unreleased': 4.0,
      'physical': 10.0,
      'min_stock': 2.0,
    }),
  ];

  @override
  Future<List<BodegaClaim>> fetchClaims({
    bool openOnly = true,
    String query = '',
  }) async => [claim];

  @override
  Future<BodegaClaim> lookupClaim(String receipt) async {
    if (receipt != claim.transactionNo) {
      throw BodegaServiceException(
        'No sale has the receipt number "$receipt".',
        code: 'NO_BODEGA_CLAIM',
      );
    }
    return claim;
  }

  @override
  Future<BodegaRelease> release(BodegaReleaseRequest request) async {
    releases.add(request);
    await hold?.future;
    claim = BodegaClaim.fromJson(
      _claimJson(remaining: 2, releases: [_releaseJson()]),
    );
    return BodegaRelease.fromJson(_releaseJson());
  }

  @override
  Future<List<BodegaDelivery>> fetchDeliveries({String status = ''}) async => [
    for (final delivery in deliveries)
      if (status.isEmpty || delivery.status == status) delivery,
  ];

  @override
  Future<BodegaDelivery> confirmDelivery(
    int id,
    BodegaDeliveryConfirmation confirmation,
  ) async {
    confirmations.add(confirmation);
    return BodegaDelivery.fromJson(_deliveryJson(status: 'CHECKED'));
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(this.account) : super(_UnusedAuthService());
  final User account;

  @override
  Future<User?> restoreSession() async => account;

  @override
  Future<User> login(String identifier, String password) async => account;

  @override
  Future<void> logout() async {}
}

class _UnusedAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async =>
      throw const AuthException('not used');

  @override
  Future<void> logout() async {}
}

Future<AuthViewmodel> _auth(Role role, {int id = 70}) async {
  final auth = AuthViewmodel(
    _FakeAuthRepository(
      User(
        id: id,
        username: 'u$id',
        email: 'u$id@demo.ph',
        fullName: 'User $id',
        role: role,
        roles: [role],
      ),
    ),
  );
  await auth.login('u', 'p');
  return auth;
}

Future<void> _pump(WidgetTester tester, AuthViewmodel auth, Widget page) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(theme: AppTheme.lightTheme, home: page),
    ),
  );
  await tester.pumpAndSettle();
}

/// Scrolls [finder] to the middle of a phone screen and taps it: at 844 px the
/// bottom edge is under the shell's overlay, so `ensureVisible` alone is not
/// enough.
Future<void> _tapOnPhone(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.drag(find.byType(ListView).first, const Offset(0, -300));
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('wire shapes', () {
    test('a claim reads numbers and strings alike', () {
      final claim = BodegaClaim.fromJson(
        _claimJson(remaining: 4, releases: [_releaseJson()]),
      );
      expect(claim.lines.single.remaining, 4);
      expect(claim.releases.single.lines.single.qty, 2);
      expect(claim.releases.single.summary, '2 CU.M Gravel — 3/4');
    });

    test('a delivery reads pending and checked lines', () {
      final pending = BodegaDelivery.fromJson(_deliveryJson());
      expect(pending.isPending, isTrue);
      expect(pending.lines.single.goodQty, isNull);
      expect(pending.lines.single.isWhole, isTrue);
      final checked = BodegaDelivery.fromJson(_deliveryJson(status: 'CHECKED'));
      expect(checked.lines.single.missingQty, 5);
      expect(checked.damagedTotal, 15);
    });

    test('a release request sends base quantities to two decimals', () {
      const request = BodegaReleaseRequest(
        receipt: 'TRX-1',
        receivedBy: 'Pedro',
        lines: [(variantId: 5, locationId: 2, qty: 1.5)],
      );
      expect(request.toJson()['lines'], [
        {'variant': 5, 'location': 2, 'qty': '1.50'},
      ]);
    });
  });

  group('the /bodega/ fence', () {
    String? go(String role, String location) => AppRoutes.redirectFor(
      isAuthenticated: true,
      role: role,
      location: location,
    );

    test('the checker lands on Pick-ups and stays inside /bodega/', () {
      expect(
        AppRoutes.dashboardForRole(AppAreas.bodega),
        AppRoutes.bodegaPickups,
      );
      expect(go('bodega', AppRoutes.login), AppRoutes.bodegaPickups);
      expect(go('bodega', AppRoutes.bodegaDeliveries), isNull);
      for (final elsewhere in [
        AppRoutes.posDashboard,
        AppRoutes.inventoryStock,
        AppRoutes.inventoryReceiving,
        AppRoutes.salesDashboard,
        AppRoutes.adminDashboard,
      ]) {
        expect(
          go('bodega', elsewhere),
          AppRoutes.bodegaPickups,
          reason: elsewhere,
        );
      }
    });

    test('nobody else opens /bodega/', () {
      expect(go('pos', AppRoutes.bodegaPickups), AppRoutes.posDashboard);
      expect(
        go('inventory', AppRoutes.bodegaStock),
        AppRoutes.inventoryDashboard,
      );
      expect(go('sales', AppRoutes.bodegaHistory), AppRoutes.salesDashboard);
    });
  });

  group('phone screens', () {
    testWidgets('stock is read only and the menu is the Bodega only', (
      tester,
    ) async {
      final repo = _FakeBodegaRepository();
      await _pump(
        tester,
        await _auth(_checkerRole),
        BodegaStockPage(viewmodel: BodegaViewmodel(repository: repo)),
      );
      expect(find.text('Gravel — 3/4'), findsOneWidget);
      expect(find.text('Should be on site: 10 CU.M'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing, reason: 'read only');
      await tester.tap(find.byTooltip('Open menu').first);
      await tester.pumpAndSettle();
      expect(find.text('Pick-ups'), findsWidgets);
      expect(find.text('Deliveries to check'), findsOneWidget);
      expect(find.text('New transaction'), findsNothing);
      expect(find.text('Receiving'), findsNothing);
    });

    testWidgets('scanning the receipt QR opens its claim', (tester) async {
      final repo = _FakeBodegaRepository();
      await _pump(
        tester,
        await _auth(_checkerRole),
        BodegaPickupsPage(
          viewmodel: BodegaViewmodel(repository: repo),
          scanner: (_) async => 'TRX-20261117-0007',
        ),
      );
      expect(
        find.byKey(const ValueKey('bodega-deliveries-banner')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('bodega-scan')));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for pick-up'), findsWidgets);
      expect(find.byKey(const ValueKey('release-qty-5.2')), findsOneWidget);
    });

    testWidgets('a release refuses more than is left without a request', (
      tester,
    ) async {
      final repo = _FakeBodegaRepository();
      await _pump(
        tester,
        await _auth(_checkerRole),
        BodegaPickupsPage(
          viewmodel: BodegaViewmodel(repository: repo),
          scanner: (_) async => 'TRX-20261117-0007',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('bodega-scan')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('release-qty-5.2')),
        '5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('release-received-by')),
        'Pedro',
      );
      await _tapOnPhone(tester, find.byKey(const ValueKey('bodega-release')));
      await tester.pumpAndSettle();
      expect(find.textContaining('only 4 CU.M'), findsOneWidget);
      expect(repo.releases, isEmpty);
    });

    testWidgets('a release sends what was typed, once', (tester) async {
      final repo = _FakeBodegaRepository()..hold = Completer<void>();
      await _pump(
        tester,
        await _auth(_checkerRole),
        BodegaPickupsPage(
          viewmodel: BodegaViewmodel(repository: repo),
          scanner: (_) async => 'TRX-20261117-0007',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('bodega-scan')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('release-qty-5.2')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('release-received-by')),
        'Pedro',
      );
      await tester.enterText(
        find.byKey(const ValueKey('release-plate')),
        'ABC 123',
      );
      final button = find.byKey(const ValueKey('bodega-release'));
      await tester.ensureVisible(button);
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.tap(button, warnIfMissed: false);
      repo.hold!.complete();
      await tester.pumpAndSettle();

      expect(repo.releases, hasLength(1));
      final sent = repo.releases.single.toJson();
      expect(sent['receipt'], 'TRX-20261117-0007');
      expect(sent['received_by'], 'Pedro');
      expect(sent['plate_no'], 'ABC 123');
      expect(sent['lines'], [
        {'variant': 5, 'location': 2, 'qty': '2.00'},
      ]);
    });

    testWidgets('a delivery check sends good and damaged per line', (
      tester,
    ) async {
      final repo = _FakeBodegaRepository();
      await _pump(
        tester,
        await _auth(_checkerRole),
        BodegaDeliveriesPage(viewmodel: BodegaViewmodel(repository: repo)),
      );
      expect(find.text('Delivered: 1,000 PC'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('delivery-good-41')),
        '980',
      );
      await tester.enterText(
        find.byKey(const ValueKey('delivery-damaged-41')),
        '15',
      );
      await tester.pump();
      expect(find.textContaining('5 PC missing'), findsOneWidget);
      final confirm = find.byKey(const ValueKey('delivery-confirm-4'));
      await _tapOnPhone(tester, confirm);
      await tester.pumpAndSettle();
      expect(repo.confirmations, hasLength(1));
      expect(repo.confirmations.single.toJson()['lines'], [
        {
          'line': 41,
          'good_qty': '980.00',
          'damaged_qty': '15.00',
          'remarks': '',
        },
      ]);
      expect(find.text('Recently checked'), findsOneWidget);
    });

    testWidgets('more than was delivered is refused without a request', (
      tester,
    ) async {
      final repo = _FakeBodegaRepository();
      await _pump(
        tester,
        await _auth(_checkerRole),
        BodegaDeliveriesPage(viewmodel: BodegaViewmodel(repository: repo)),
      );
      await tester.enterText(
        find.byKey(const ValueKey('delivery-damaged-41')),
        '20',
      );
      final confirm = find.byKey(const ValueKey('delivery-confirm-4'));
      await _tapOnPhone(tester, confirm);
      await tester.pumpAndSettle();
      expect(find.textContaining('more than the 1,000 PC'), findsOneWidget);
      expect(repo.confirmations, isEmpty);
    });
  });
}
