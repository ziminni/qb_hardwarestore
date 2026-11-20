// The Bodega Checker's phone app (owner 2026-11-18), at phone size (390 x 844):
//   * a brand header and a bottom bar: Home | Arrivals | Scan | Pick-ups | Profile;
//   * Home: two count squares, the pick-up box three rows tall (more scroll),
//     then the arrivals waiting for the check;
//   * an arrival report needs a photo of every item; Complete / Damaged /
//     Missing with an optional quantity becomes the server's good / damaged;
//   * Scan opens the receipt's claim; Profile shows who is signed in;
//   * a new arrival raises one phone notification, once.

import 'dart:convert';

import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/bodega.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/bodega_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/bodega_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/bodega/mobile/arrival_alerts.dart';
import 'package:client/features/bodega/mobile/arrival_report.dart';
import 'package:client/features/bodega/mobile/bodega_home_tab.dart';
import 'package:client/features/bodega/mobile/bodega_mobile_shell.dart';
import 'package:client/features/bodega/viewmodels/bodega_viewmodel.dart';
import 'package:client/features/bodega/views/bodega_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A real 1x1 PNG, so the photo box can draw it.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

const _checker = User(
  id: 3,
  username: 'checker',
  email: 'c@x.com',
  fullName: 'Juan Checker',
  role: Role(id: 9, name: 'bodega', displayName: 'Bodega Checker'),
);

Map<String, dynamic> _claim(int n) => {
  'sale': 100 + n,
  'transaction_no': 'TRX-20261118-000$n',
  'or_number': 'OR-20261118-000$n',
  'customer_name': 'Customer $n',
  'sold_at': '2026-11-18T09:00:00+08:00',
  'is_open': true,
  'remaining_total': 4,
  'lines': [
    {
      'variant': 5,
      'label': 'Gravel — 3/4',
      'unit': 'CU.M',
      'location': 2,
      'location_name': 'Bodega',
      'sold': 4.0,
      'released': 0.0,
      'remaining': 4.0,
    },
  ],
  'releases': const [],
};

Map<String, dynamic> _line(int id, String label, {String photo = ''}) => {
  'id': id,
  'variant': id,
  'label': label,
  'unit': 'BAG',
  'is_whole': true,
  'delivered_qty': '10.00',
  'good_qty': null,
  'damaged_qty': null,
  'missing_qty': null,
  'remarks': '',
  'photo_url': photo,
};

Map<String, dynamic> _delivery(int id, {String status = 'PENDING'}) => {
  'id': id,
  'number': 'BD-20261118-000$id',
  'location_name': 'Bodega',
  'supplier_name': 'Holcim',
  'received_by_name': 'Stock Er',
  'status': status,
  'checked_by_name': '',
  'checked_at': null,
  'notes': '',
  'created_at': '2026-11-18T08:00:00+08:00',
  'lines': [_line(id * 10 + 1, 'Cement 40kg'), _line(id * 10 + 2, 'Nails 2in')],
};

class _FakeRepository extends BodegaRepository {
  _FakeRepository({this.claimCount = 5, this.deliveryIds = const [1, 2]})
    : super(service: BodegaService());

  int claimCount;
  List<int> deliveryIds;
  bool offline = false;
  final uploads = <(int, int)>[];
  final releasedRequests = <BodegaReleaseRequest>[];
  int fetches = 0;
  final confirmations = <BodegaDeliveryConfirmation>[];

  @override
  Future<List<BodegaClaim>> fetchClaims({
    bool openOnly = true,
    String query = '',
  }) async {
    if (offline) {
      throw const BodegaServiceException(
        'Cannot connect to the BuildPro server.',
      );
    }
    return [
      for (var i = 1; i <= claimCount; i++) BodegaClaim.fromJson(_claim(i)),
    ];
  }

  @override
  Future<BodegaClaim> lookupClaim(String receipt) async {
    if (offline) {
      throw const BodegaServiceException(
        'Cannot connect to the BuildPro server.',
      );
    }
    for (var i = 1; i <= claimCount; i++) {
      final claim = BodegaClaim.fromJson(_claim(i));
      if (claim.orNumber == receipt || claim.transactionNo == receipt) {
        return claim;
      }
    }
    throw BodegaServiceException('No sale has the receipt number "$receipt".');
  }

  @override
  Future<BodegaRelease> release(BodegaReleaseRequest request) async {
    if (offline) {
      throw const BodegaServiceException(
        'Cannot connect to the BuildPro server.',
      );
    }
    releasedRequests.add(request);
    return BodegaRelease(
      id: releasedRequests.length,
      number: 'BR-20261118-000${releasedRequests.length}',
      transactionNo: request.receipt,
      customerName: 'Customer 1',
      checkerName: 'Juan Checker',
      receivedBy: request.receivedBy,
      plateNo: request.plateNo,
      notes: request.notes,
      createdAt: DateTime(2026, 11, 18, 10),
      lines: const [],
    );
  }

  @override
  Future<List<BodegaDelivery>> fetchDeliveries({String status = ''}) async {
    fetches++;
    return [
      for (final id in deliveryIds) BodegaDelivery.fromJson(_delivery(id)),
    ];
  }

  @override
  Future<BodegaDelivery> uploadLinePhoto(
    int deliveryId,
    int lineId,
    List<int> bytes, {
    String filename = 'item.jpg',
  }) async {
    uploads.add((deliveryId, lineId));
    final json = _delivery(deliveryId);
    json['lines'] = [
      for (final line in json['lines'] as List)
        {
          ...line as Map<String, dynamic>,
          'photo_url': line['id'] == lineId
              ? 'http://x/p.jpg'
              : line['photo_url'],
        },
    ];
    return BodegaDelivery.fromJson(json);
  }

  @override
  Future<BodegaDelivery> confirmDelivery(
    int id,
    BodegaDeliveryConfirmation confirmation,
  ) async {
    confirmations.add(confirmation);
    deliveryIds = [
      for (final other in deliveryIds)
        if (other != id) other,
    ];
    return BodegaDelivery.fromJson(_delivery(id, status: 'CHECKED'));
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(AuthService());

  @override
  Future<User?> restoreSession() async => _checker;

  @override
  Future<User> login(String identifier, String password) async => _checker;

  @override
  Future<void> logout() async {}
}

class _Alerts implements AlertSender {
  final sent = <String>[];

  @override
  Future<void> send(String title, String body) async =>
      sent.add('$title|$body');
}

Future<({AuthViewmodel auth, _FakeRepository repo, _Alerts alerts})> _pump(
  WidgetTester tester, {
  int claims = 5,
  List<int> deliveries = const [1, 2],
  Future<String?> Function(BuildContext)? scanner,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = AuthViewmodel(_FakeAuthRepository());
  await auth.login('checker', 'pw');
  final repo = _FakeRepository(claimCount: claims, deliveryIds: deliveries);
  final alerts = _Alerts();
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: BodegaMobileShell(
          viewmodel: BodegaViewmodel(repository: repo),
          alerts: ArrivalAlerts(sender: alerts),
          scanner: scanner,
          takePhoto: ({bool fromGallery = false}) async =>
              (bytes: _png, name: 'photo.png'),
          pollEvery: const Duration(hours: 1),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (auth: auth, repo: repo, alerts: alerts);
}

Future<void> _tab(WidgetTester tester, BodegaTab tab) async {
  await tester.tap(find.byKey(ValueKey('bodega-tab-${tab.name}')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a brand header and five tabs, Scan raised in the middle', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.byKey(const ValueKey('bodega-header')), findsOneWidget);
    expect(find.text('Queen Builders · Juan Checker'), findsOneWidget);
    for (final tab in BodegaTab.values) {
      expect(find.byKey(ValueKey('bodega-tab-${tab.name}')), findsOneWidget);
    }
    final scan = tester.getCenter(
      find.byKey(const ValueKey('bodega-tab-scan')),
    );
    final home = tester.getCenter(
      find.byKey(const ValueKey('bodega-tab-home')),
    );
    expect(scan.dx, closeTo(390 / 2, 1), reason: 'Scan is the middle button');
    expect(scan.dy, lessThan(home.dy), reason: 'Scan sits raised');
  });

  testWidgets('Home: the two squares count pick-ups and arrivals', (
    tester,
  ) async {
    await _pump(tester, claims: 5, deliveries: [1, 2]);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tile-pickups')),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tile-arrivals')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Home: the pick-up box shows three rows and scrolls the rest', (
    tester,
  ) async {
    await _pump(tester, claims: 5);

    final box = tester.getSize(find.byKey(const ValueKey('pickup-box')));
    expect(box.height, visiblePickupRows * pickupRowHeight);
    final list = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const ValueKey('pickup-list')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      list.position.maxScrollExtent,
      greaterThan(0),
      reason: 'rows 4-5 scroll',
    );
  });

  testWidgets('Home: a pick-up row keeps its date whole, on the right', (
    tester,
  ) async {
    await _pump(tester, claims: 1);

    // Seen on the phone: the date at the end of the subtitle was cut to "No…".
    final row = find.descendant(
      of: find.byKey(const ValueKey('pickup-box')),
      matching: find.byType(ListTile),
    );
    final sold = BodegaClaim.fromJson(_claim(1)).soldAt!;
    expect(
      find.descendant(of: row, matching: find.text(formatShortDate(sold))),
      findsOneWidget,
    );
  });

  testWidgets('Home: one waiting receipt is a one-row box', (tester) async {
    await _pump(tester, claims: 1);

    expect(
      tester.getSize(find.byKey(const ValueKey('pickup-box'))).height,
      pickupRowHeight,
    );
  });

  testWidgets('a report is refused until every item has its photo', (
    tester,
  ) async {
    final (:auth, :repo, :alerts) = await _pump(tester, deliveries: [1]);
    await _tab(tester, BodegaTab.arrivals);
    await tester.tap(find.byKey(const ValueKey('arrival-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('submit-report')));
    await tester.pumpAndSettle();

    expect(find.text('Take a photo of Cement 40kg.'), findsOneWidget);
    expect(repo.uploads, isEmpty);
    expect(repo.confirmations, isEmpty);
  });

  testWidgets('photos upload first, then good and damaged are sent per item', (
    tester,
  ) async {
    final (:auth, :repo, :alerts) = await _pump(tester, deliveries: [1]);
    await _tab(tester, BodegaTab.arrivals);
    await tester.tap(find.byKey(const ValueKey('arrival-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('photo-11')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('photo-12')));
    await tester.tap(find.byKey(const ValueKey('photo-12')));
    await tester.pumpAndSettle();
    // Nails: 2 of the 10 bags damaged.
    await tester.ensureVisible(find.byKey(const ValueKey('condition-12')));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('condition-12')),
        matching: find.text('Damaged'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('qty-12')));
    await tester.enterText(find.byKey(const ValueKey('qty-12')), '2');
    await tester.tap(find.byKey(const ValueKey('submit-report')));
    await tester.pumpAndSettle();

    expect(repo.uploads, [(1, 11), (1, 12)]);
    final sent = repo.confirmations.single.lines;
    expect((sent[0].lineId, sent[0].good, sent[0].damaged), (11, 10.0, 0.0));
    expect((sent[1].lineId, sent[1].good, sent[1].damaged), (12, 8.0, 2.0));
    expect(
      find.text('BD-20261118-0001 checked into the Bodega.'),
      findsOneWidget,
    );
  });

  testWidgets('Scan opens the scanned receipt\'s claim', (tester) async {
    await _pump(tester, scanner: (_) async => 'OR-20261118-0002');

    await _tab(tester, BodegaTab.scan);

    expect(find.byType(BodegaClaimCard), findsOneWidget);
    expect(find.text('OR-20261118-0002'), findsWidgets);
  });

  testWidgets('Profile: name, role, server address and log out', (
    tester,
  ) async {
    final (:auth, :repo, :alerts) = await _pump(tester);
    await _tab(tester, BodegaTab.profile);

    expect(find.text('Juan Checker'), findsOneWidget);
    expect(find.text('Bodega Checker'), findsOneWidget);
    expect(find.byKey(const ValueKey('server-address')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('log-out')));
    await tester.tap(find.byKey(const ValueKey('log-out')));
    await tester.pumpAndSettle();

    expect(auth.user, isNull);
  });

  testWidgets('each new arrival raises one phone notification, once', (
    tester,
  ) async {
    final (:auth, :repo, :alerts) = await _pump(tester, deliveries: [1]);

    expect(alerts.sent, [
      'New arrival to check|BD-20261118-0001 · Holcim · 2 items',
    ]);

    // The app comes back to the front: a real refresh, the same arrival, and
    // no second alert. Then a NEW arrival: exactly one more.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(repo.fetches, greaterThanOrEqualTo(2), reason: 'it did refresh');
    expect(alerts.sent, hasLength(1));

    repo.deliveryIds = [1, 2];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
      alerts.sent.last,
      'New arrival to check|BD-20261118-0002 · Holcim · 2 items',
    );
    expect(alerts.sent, hasLength(2));
  });

  testWidgets('the desktop pick-ups page is unchanged off a phone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthViewmodel(_FakeAuthRepository());
    await auth.login('checker', 'pw');
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: auth,
        child: MaterialApp(
          home: BodegaPickupsPage(
            viewmodel: BodegaViewmodel(repository: _FakeRepository()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(runsAsPhoneApp, isFalse, reason: 'tests run on the computer');
    expect(find.byType(BodegaMobileShell), findsNothing);
  });

  group('the report rules', () {
    BodegaDeliveryLine line({bool whole = true}) =>
        BodegaDeliveryLine.fromJson({..._line(1, 'Cement'), 'is_whole': whole});

    ({double good, double damaged})? verdict(
      ItemCondition condition,
      String qty, {
      bool whole = true,
      List<String>? errors,
    }) {
      final item = ItemReport(line(whole: whole))
        ..condition = condition
        ..qtyText = qty;
      return item.verdict((message) => errors?.add(message));
    }

    test('Complete is all good', () {
      expect(verdict(ItemCondition.complete, ''), (good: 10.0, damaged: 0.0));
    });

    test('Damaged with no quantity is the whole line', () {
      expect(verdict(ItemCondition.damaged, ''), (good: 0.0, damaged: 10.0));
    });

    test('Damaged with a quantity leaves the rest good', () {
      expect(verdict(ItemCondition.damaged, '3'), (good: 7.0, damaged: 3.0));
    });

    test('Missing is neither good nor damaged: the server writes it off', () {
      expect(verdict(ItemCondition.missing, ''), (good: 0.0, damaged: 0.0));
      expect(verdict(ItemCondition.missing, '4'), (good: 6.0, damaged: 0.0));
    });

    test(
      'more than arrived, a fraction of a whole unit, or not a number is refused',
      () {
        final errors = <String>[];
        expect(verdict(ItemCondition.damaged, '11', errors: errors), isNull);
        expect(verdict(ItemCondition.damaged, '1.5', errors: errors), isNull);
        expect(verdict(ItemCondition.damaged, '0', errors: errors), isNull);
        expect(errors, [
          'Cement: only 10 BAG arrived.',
          'Cement is counted in whole BAG.',
          'Cement: "0" is not a quantity.',
        ]);
        expect(verdict(ItemCondition.damaged, '1.5', whole: false), (
          good: 8.5,
          damaged: 1.5,
        ));
      },
    );
  });

  test('offline snapshot lookup and release outbox queue replay when back online', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = _FakeRepository(claimCount: 2);
    final vm = BodegaViewmodel(repository: repo);

    // 1. Online load caches the open claims snapshot.
    await vm.loadHome();
    expect(vm.openClaims, hasLength(2));
    expect(vm.usingOfflineSnapshot, isFalse);

    // 2. Phone enters warehouse Wi-Fi dead zone: lookup and release use snapshot + outbox.
    repo.offline = true;
    final found = await vm.lookup('OR-20261118-0001');
    expect(found, isTrue);
    expect(vm.usingOfflineSnapshot, isTrue);
    expect(vm.claim?.transactionNo, 'TRX-20261118-0001');

    final queued = await vm.release(
      const BodegaReleaseRequest(
        receipt: 'TRX-20261118-0001',
        receivedBy: 'Pedro Driver',
        plateNo: 'ABC-123',
        lines: [(variantId: 5, locationId: 2, qty: 4.0)],
      ),
    );
    expect(queued?.number, 'QUEUED-OFFLINE');
    expect(vm.queuedReleaseCount, 1);
    expect(vm.claim?.isOpen, isFalse);
    expect(vm.openClaims.map((c) => c.transactionNo), ['TRX-20261118-0002']);

    // 3. Phone reconnects to Wi-Fi: loadHome replays the outbox with Idempotency-Key.
    repo.offline = false;
    await vm.loadHome();
    expect(vm.queuedReleaseCount, 0);
    expect(vm.usingOfflineSnapshot, isFalse);
    expect(repo.releasedRequests, hasLength(1));
    expect(repo.releasedRequests.single.idempotencyKey, isNotEmpty);
    expect(repo.releasedRequests.single.receivedBy, 'Pedro Driver');
  });
}
