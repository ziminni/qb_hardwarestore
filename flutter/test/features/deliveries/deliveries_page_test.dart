// Phase 5 F3 (decision 18): the delivery schedule screen.
//
// Pinned here, in the shells the routes mount:
//   * a row says who is waiting, when, where and for what fee;
//   * a move is offered only where the status allows it (a finished slip shows
//     none), because the server answers 409 to anything else;
//   * a failure NEEDS a reason, typed in the dialog;
//   * a refusal shows the server's sentence and the list re-reads;
//   * the slip prints through the existing 80 mm PDF path;
//   * at 760 px with 1.3x text and the real fonts nothing clips.

import 'dart:io';

import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/delivery_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/deliveries/viewmodels/deliveries_viewmodel.dart';
import 'package:client/features/deliveries/views/deliveries_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Delivery _delivery({
  int id = 1,
  String no = 'DLV-20261111-0001',
  DeliveryStatus status = DeliveryStatus.scheduled,
  String customer = 'Maria Santos',
  String contact = 'Maria Santos',
  String phone = '09171234567',
  DateTime? scheduledDate,
  double fee = 50,
  List<DeliveryItem> items = const [
    DeliveryItem(name: 'Portland cement', unit: 'BAG', qty: 2),
  ],
}) => Delivery(
  id: id,
  deliveryNo: no,
  saleId: 9,
  salesOrderId: null,
  transactionNo: 'TRX-20261111-0009',
  orderNo: '',
  customerId: 3,
  customerName: customer,
  address: '12 Mabini St, Cebu City',
  contactName: contact,
  contactPhone: phone,
  scheduledDate: scheduledDate ?? DateTime(2026, 11, 12),
  fee: fee,
  status: status,
  failureReason: status == DeliveryStatus.failed ? 'Customer not home.' : '',
  items: items,
  createdByName: 'Maria Santos',
  createdAt: DateTime(2026, 11, 11, 9),
);

class _StubService extends DeliveryService {
  _StubService({List<Delivery>? deliveries})
    : deliveries = deliveries ?? [_delivery()];

  List<Delivery> deliveries;
  final List<String> calls = [];
  DeliveryServiceException? moveFailure;

  @override
  Future<List<Delivery>> fetchAll({
    DeliveryStatus? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    calls.add('load');
    return deliveries;
  }

  @override
  Future<Delivery> start(int id) async {
    calls.add('start:$id');
    final boom = moveFailure;
    if (boom != null) throw boom;
    return _delivery(id: id, status: DeliveryStatus.outForDelivery);
  }

  @override
  Future<Delivery> deliver(int id) async {
    calls.add('deliver:$id');
    final boom = moveFailure;
    if (boom != null) throw boom;
    return _delivery(id: id, status: DeliveryStatus.delivered);
  }

  @override
  Future<Delivery> fail(int id, String reason) async {
    calls.add('fail:$id:$reason');
    final boom = moveFailure;
    if (boom != null) throw boom;
    return _delivery(id: id, status: DeliveryStatus.failed);
  }
}

class _RecordingPrinter implements DeliverySlipPrinter {
  final List<Delivery> printed = [];

  @override
  Future<void> print(Delivery delivery) async {
    printed.add(delivery);
  }
}

Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    ('OpenSans', ['OpenSans-Regular.ttf', 'OpenSans-Bold.ttf']),
    ('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  Size size = const Size(1400, 1000),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewmodel>(
          create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(_loadAppFonts);

  testWidgets(
    'a scheduled slip shows what is going out, when and for what fee',
    (tester) async {
      final service = _StubService();
      await _pump(
        tester,
        InventoryDeliveriesPage(
          viewmodel: DeliveriesViewmodel(service: service),
        ),
      );

      expect(find.text('DLV-20261111-0001'), findsOneWidget);
      expect(find.text('Sale TRX-20261111-0009'), findsOneWidget);
      expect(find.text('Maria Santos'), findsWidgets);
      expect(find.text('09171234567'), findsOneWidget);
      expect(find.text(formatDate(DateTime(2026, 11, 12))), findsOneWidget);
      expect(find.text(formatPeso(50)), findsOneWidget);
      // The chip in the filter bar says it too; the badge is the row's own word.
      expect(find.text('Scheduled'), findsWidgets);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('delivery.1')),
          matching: find.text('Scheduled'),
        ),
        findsOneWidget,
      );
      // A scheduled slip has both a start and a failure available.
      expect(find.byKey(const ValueKey('delivery-start-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('delivery-failed-1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('delivery-delivered-1')),
        findsNothing,
        reason: 'nothing is out for delivery yet',
      );
    },
  );

  testWidgets('a finished slip offers no move, only its slip', (tester) async {
    final service = _StubService(
      deliveries: [_delivery(id: 2, status: DeliveryStatus.delivered)],
    );
    await _pump(
      tester,
      SalesDeliveriesPage(viewmodel: DeliveriesViewmodel(service: service)),
    );

    expect(find.byKey(const ValueKey('delivery-start-2')), findsNothing);
    expect(find.byKey(const ValueKey('delivery-delivered-2')), findsNothing);
    expect(find.byKey(const ValueKey('delivery-failed-2')), findsNothing);
    expect(find.byKey(const ValueKey('delivery-slip-2')), findsOneWidget);
  });

  testWidgets('a failed delivery needs a reason before it is sent', (
    tester,
  ) async {
    final service = _StubService();
    await _pump(
      tester,
      InventoryDeliveriesPage(viewmodel: DeliveriesViewmodel(service: service)),
    );

    await tester.tap(find.byKey(const ValueKey('delivery-failed-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Mark failed'));
    await tester.pumpAndSettle();
    expect(find.text('A failed delivery needs a reason.'), findsOneWidget);
    expect(
      service.calls.any((call) => call.startsWith('fail')),
      isFalse,
      reason: 'nothing is posted without the reason the server stores',
    );

    await tester.enterText(
      find.byKey(const ValueKey('delivery-failure-reason')),
      'Customer not home.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Mark failed'));
    await tester.pumpAndSettle();

    expect(service.calls, contains('fail:1:Customer not home.'));
    expect(find.text('Failed'), findsWidgets);
  });

  testWidgets('a refusal shows the server sentence and re-reads the list', (
    tester,
  ) async {
    final service = _StubService()
      ..moveFailure = const DeliveryServiceException(
        'Delivery DLV-20261111-0001 is DELIVERED and cannot move again.',
        code: 'DELIVERY_TRANSITION_INVALID',
        status: 'DELIVERED',
      );
    await _pump(
      tester,
      AdminDeliveriesPage(viewmodel: DeliveriesViewmodel(service: service)),
    );

    await tester.tap(find.byKey(const ValueKey('delivery-start-1')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('cannot move again'),
      findsOneWidget,
      reason: 'the server names the state; a canned sentence cannot',
    );
    expect(service.calls, ['load', 'start:1', 'load']);
  });

  testWidgets('printing a slip goes through the injected printer', (
    tester,
  ) async {
    final printer = _RecordingPrinter();
    final service = _StubService(
      deliveries: [
        _delivery(
          items: const [
            DeliveryItem(
              name: 'Portland cement',
              unit: 'BAG',
              qty: 2,
              storedAtName: 'Bodega',
            ),
          ],
        ),
      ],
    );
    await _pump(
      tester,
      InventoryDeliveriesPage(
        viewmodel: DeliveriesViewmodel(service: service),
        printer: printer,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('delivery-slip-1')));
    await tester.pumpAndSettle();

    expect(printer.printed, hasLength(1));
    expect(printer.printed.single.documentNo, 'DLV-20261111-0001');
  });

  testWidgets(
    '760 px at 1.3x text, the page and the reason dialog render whole',
    (tester) async {
      final service = _StubService();
      await _pump(
        tester,
        InventoryDeliveriesPage(
          viewmodel: DeliveriesViewmodel(service: service),
        ),
        size: const Size(760, 900),
        scale: 1.3,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Deliveries'), findsWidgets);

      // At 760 x 900 the actions sit below the fold: scroll to them the way a
      // reader would.
      await tester.ensureVisible(
        find.byKey(const ValueKey('delivery-failed-1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delivery-failed-1')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        find.widgetWithText(FilledButton, 'Mark failed').hitTestable(),
        findsOneWidget,
      );
    },
  );
}
