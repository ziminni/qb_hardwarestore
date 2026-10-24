// Phase 3 Task 0 (U) — "Notifications" in the sales, inventory and admin shells
// was `OutlinedButton.icon(onPressed: () {}, ...)`: three copies of a button
// that opened nothing.
//
// It now opens ONE shared read-only sheet of unresolved alerts from
// `GET /api/v1/alerts/` (readable by every authenticated user — ENDPOINTS.md).
// Resolving an alert stays Phase 4, so this sheet never writes: it loads,
// states emptiness plainly, and offers a retry when the read fails.
//
// The alerts source is reused, not duplicated: `InventoryService.fetchAlerts`
// and `SystemAlert` are the existing authority (decision 13).

import 'dart:async';

import 'package:client/data/models/system_alert.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/shared/widgets/notifications_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubInventoryService extends InventoryService {
  _StubInventoryService() : super();

  List<SystemAlert> alerts = const [];
  String? failure;
  int calls = 0;

  /// When set, the read waits on this gate so the loading state is observable
  /// instead of resolving inside `pumpWidget`.
  Completer<List<SystemAlert>>? gate;

  @override
  Future<List<SystemAlert>> fetchAlerts() async {
    calls++;
    final gate = this.gate;
    // The gate carries the payload: completing it is what the read returns.
    if (gate != null) return gate.future;
    final failure = this.failure;
    if (failure != null) throw InventoryServiceException(failure);
    return alerts;
  }
}

SystemAlert _alert({
  required int id,
  String type = 'LOW_STOCK',
  required String message,
  bool resolved = false,
}) => SystemAlert(
  id: id,
  type: SystemAlertType.fromApiValue(type),
  variantId: 5,
  message: message,
  isResolved: resolved,
  createdAt: DateTime(2026, 10, 24, 9),
);

Future<void> _pumpSheet(
  WidgetTester tester,
  _StubInventoryService service,
) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: NotificationsSheet(service: service)),
    ),
  );
}

void main() {
  testWidgets('shows a spinner while the alerts are loading', (tester) async {
    final gate = Completer<List<SystemAlert>>();
    final service = _StubInventoryService()..gate = gate;

    await _pumpSheet(tester, service);
    await tester.pump();

    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'a sheet that renders blank while waiting looks broken',
    );

    gate.complete([_alert(id: 1, message: 'Cement 40kg is below threshold')]);
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Cement 40kg is below threshold'), findsOneWidget);
  });

  testWidgets('lists the UNRESOLVED alerts and drops the resolved ones', (
    tester,
  ) async {
    final service = _StubInventoryService()
      ..alerts = [
        _alert(id: 1, message: 'Cement 40kg is below threshold'),
        _alert(
          id: 2,
          type: 'OUT_OF_STOCK',
          message: 'Tiles 60x60 is out of stock',
        ),
        _alert(id: 3, message: 'Old alert, already handled', resolved: true),
      ];

    await _pumpSheet(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('Cement 40kg is below threshold'), findsOneWidget);
    expect(find.text('Tiles 60x60 is out of stock'), findsOneWidget);
    expect(find.text('Low stock'), findsWidgets);
    expect(find.text('Out of stock'), findsWidgets);
    expect(
      find.text('Old alert, already handled'),
      findsNothing,
      reason: 'resolved alerts are Phase 4 history, not a notification',
    );
    expect(find.text('No unresolved alerts.'), findsNothing);
  });

  testWidgets('an empty alert feed says so instead of showing a blank sheet', (
    tester,
  ) async {
    final service = _StubInventoryService()
      ..alerts = [_alert(id: 3, message: 'Handled', resolved: true)];

    await _pumpSheet(tester, service);
    await tester.pumpAndSettle();

    expect(find.text('No unresolved alerts.'), findsOneWidget);
  });

  testWidgets('a failed read shows the message and a working Retry', (
    tester,
  ) async {
    final service = _StubInventoryService()
      ..failure = 'Cannot connect to the BuildPro server.'
      ..alerts = [_alert(id: 1, message: 'Cement 40kg is below threshold')];

    await _pumpSheet(tester, service);
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot connect'), findsOneWidget);
    final retry = find.widgetWithText(TextButton, 'Retry');
    expect(retry, findsOneWidget);
    expect(service.calls, 1);

    service.failure = null;
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot connect'), findsNothing);
    expect(find.text('Cement 40kg is below threshold'), findsOneWidget);
    expect(service.calls, 2, reason: 'the retry must really re-read the feed');
  });

  testWidgets('the shell button opens the sheet', (tester) async {
    final service = _StubInventoryService()
      ..alerts = [_alert(id: 1, message: 'Cement 40kg is below threshold')];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: NotificationsButton(service: service)),
      ),
    );

    // Tapping is what loads: a shell that fetched on build would hit the API
    // on every dashboard render.
    expect(service.calls, 0);
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsSheet), findsOneWidget);
    expect(find.text('Cement 40kg is below threshold'), findsOneWidget);
    expect(service.calls, 1);
  });

  testWidgets('the sheet is read-only: nothing resolves or creates an alert', (
    tester,
  ) async {
    final service = _StubInventoryService()
      ..alerts = [_alert(id: 1, message: 'Cement 40kg is below threshold')];

    await _pumpSheet(tester, service);
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.textContaining('Resolve'),
      findsNothing,
      reason: 'resolving is Phase 4; there is no endpoint call to offer',
    );
  });
}
