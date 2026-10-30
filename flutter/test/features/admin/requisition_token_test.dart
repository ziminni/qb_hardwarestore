// The release token: approving a requisition mints it, and the cashier must
// type it at Release materials. Before 2026-10-30 no screen showed it, and the
// viewmodel dropped the one the approve call returned, so the approve, token,
// release flow could not be finished in the app.

import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/admin/viewmodels/admin_requisitions_viewmodel.dart';
import 'package:client/features/admin/views/requisitions_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubRequisitions extends RequisitionRepository {
  _StubRequisitions(this.rows);
  final List<Requisition> rows;

  @override
  Future<List<Requisition>> fetchRequisitions() async => rows;

  @override
  Future<String> approve(int requisitionId) async =>
      '7f3c2a10-0000-4000-8000-00000000000$requisitionId';
}

Requisition _req(int id, String status, {String? token}) => Requisition(
  id: id,
  reqNumber: 'REQ-000$id',
  rawStatus: status,
  projectName: '2-Storey House - Mandaue',
  projectCustomerName: 'Dela Cruz Construction',
  requestedByName: 'Fore Man',
  items: const [],
  token: token,
);

const _approvedToken = '7f3c2a10-0000-4000-8000-000000000001';

Future<void> _pump(WidgetTester tester, AdminRequisitionsViewmodel vm) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(home: RequisitionsPage(viewmodel: vm)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Captures what the app writes to the clipboard.
String? _clipboard;
void _mockClipboard(WidgetTester tester) {
  _clipboard = null;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        _clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

void main() {
  test('approving keeps the token the server returned', () async {
    final vm = AdminRequisitionsViewmodel(
      repository: _StubRequisitions([_req(1, 'SUBMITTED')]),
    );
    await vm.load();

    expect(await vm.approve(1), isTrue);

    expect(vm.requisitions.single.token, _approvedToken);
  });

  testWidgets('right after Approve, the token is shown with Copy', (
    tester,
  ) async {
    _mockClipboard(tester);
    final vm = AdminRequisitionsViewmodel(
      repository: _StubRequisitions([_req(1, 'SUBMITTED')]),
    );
    await _pump(tester, vm);

    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    expect(
      find.descendant(of: dialog, matching: find.text(_approvedToken)),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: dialog, matching: find.text('Copy token')),
    );
    await tester.pumpAndSettle();
    expect(_clipboard, _approvedToken);
  });

  testWidgets('an approved row shows its token only after Show', (
    tester,
  ) async {
    _mockClipboard(tester);
    final vm = AdminRequisitionsViewmodel(
      repository: _StubRequisitions([
        _req(1, 'APPROVED', token: _approvedToken),
      ]),
    );
    await _pump(tester, vm);

    // A bearer credential: present, but not on screen until asked for.
    expect(find.text('Release token'), findsOneWidget);
    expect(find.text(_approvedToken), findsNothing);

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text(_approvedToken), findsOneWidget);

    await tester.tap(find.text('Copy token'));
    await tester.pumpAndSettle();
    expect(_clipboard, _approvedToken);
  });

  testWidgets('a row without a token shows no token panel', (tester) async {
    final vm = AdminRequisitionsViewmodel(
      repository: _StubRequisitions([
        _req(1, 'SUBMITTED'),
        _req(2, 'APPROVED'),
      ]),
    );
    await _pump(tester, vm);

    expect(find.text('Release token'), findsNothing);
  });
}
