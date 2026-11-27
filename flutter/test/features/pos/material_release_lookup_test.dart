import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:client/features/pos/views/material_release_page.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _Repository extends RequisitionRepository {
  int releases = 0;
  int selections = 0;
  bool offline = false;
  final tokens = <String>[];

  @override
  Future<List<Requisition>> fetchReleaseQueue() async {
    if (offline) throw const RequisitionServiceException('Store offline');
    return const [
      Requisition(
        id: 3,
        reqNumber: 'REQ-3',
        rawStatus: 'ACCEPTED',
        projectName: 'House Build',
        projectCustomerName: 'Builder Corp',
        requestedByName: 'Ana',
        items: [],
      ),
      Requisition(
        id: 4,
        reqNumber: 'REQ-4',
        rawStatus: 'PARTIAL',
        projectName: 'School',
        projectCustomerName: 'City',
        requestedByName: 'Ben',
        items: [],
      ),
    ];
  }

  @override
  Future<TokenVerification> verifyRequest(int id) async {
    selections++;
    return verifyToken('selected-token');
  }

  @override
  Future<TokenVerification> verifyToken(String token) async {
    tokens.add(token);
    return TokenVerification(
      token: token,
      requisitionId: 3,
      reqNumber: 'REQ-3',
      project: 'House Build',
      customer: 'Builder Corp',
      items: const [
        VerifiedRequisitionItem(
          id: 1,
          variantId: 7,
          variantName: 'Cement 40kg',
          quantity: 10,
          remaining: 10,
          availability: LineAvailability.full,
          releasable: 10,
        ),
      ],
    );
  }

  @override
  Future<ReleaseResult> release(
    String token, {
    Map<int, double>? quantities,
  }) async {
    releases++;
    return const ReleaseResult(
      transactionId: 42,
      transactionNo: 'TXN-42',
      status: ReleaseStatus.released,
      items: [],
      grandTotal: 100,
      ledgerId: 9,
      balanceDue: 100,
    );
  }

  @override
  Future<PosReceipt> fetchReleaseReceipt(int id) async {
    expect(id, 42);
    return PosReceipt(
      reference: 'TXN-42',
      officialReceiptNumber: 'OR-42',
      createdAt: DateTime(2026, 11, 15),
      lines: const [],
      paymentMethod: 'CREDIT',
      amountPaid: 0,
      total: 100,
    );
  }
}

class _Printer implements ReceiptPrinter {
  bool fail = false;
  final receipts = <PosReceipt>[];
  @override
  Future<void> print(PosReceipt receipt) async {
    receipts.add(receipt);
    if (fail) throw Exception('Printer offline');
  }
}

Future<MaterialReleaseViewmodel> _pump(
  WidgetTester tester,
  _Repository repo,
  _Printer printer, {
  Size size = const Size(1440, 1100),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final vm = MaterialReleaseViewmodel(repository: repo);
  addTearDown(vm.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        home: MaterialReleasePage(viewmodel: vm, printer: printer),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return vm;
}

void main() {
  test('simultaneous confirmations send only one release', () async {
    final repo = _Repository();
    final vm = MaterialReleaseViewmodel(repository: repo);
    addTearDown(vm.dispose);
    await vm.verify('manual-token');
    final first = vm.release();
    expect(await vm.release(), isFalse);
    expect(await first, isTrue);
    expect(repo.releases, 1);
  });

  testWidgets(
    'cashier searches project, selects request, confirms once and prints',
    (tester) async {
      final repo = _Repository();
      final printer = _Printer();
      final vm = await _pump(tester, repo, printer);
      // The accepted requests are listed on the page itself.
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('release.requestSearch')),
        'house',
      );
      await tester.pumpAndSettle();
      expect(find.text('REQ-4'), findsNothing);
      await tester.tap(find.text('REQ-3'));
      await tester.pumpAndSettle();
      expect(repo.selections, 1);
      expect(repo.releases, 0);
      expect(vm.verification?.token, 'selected-token');
      expect(find.textContaining('Cement 40kg'), findsWidgets);
      await tester.ensureVisible(
        find.byKey(const ValueKey('release-confirm')),
      );
      await tester.tap(find.byKey(const ValueKey('release-confirm')));
      await tester.pumpAndSettle();
      expect(repo.releases, 1);
      await tester.ensureVisible(find.text('Print receipt'));
      await tester.tap(find.text('Print receipt'));
      await tester.pumpAndSettle();
      expect(printer.receipts.single.officialReceiptNumber, 'OR-42');
      expect(repo.releases, 1);
      expect(vm.result, isNotNull);
    },
  );

  testWidgets('typed token is trimmed and Enter verifies without releasing', (
    tester,
  ) async {
    final repo = _Repository();
    await _pump(tester, repo, _Printer());
    await tester.enterText(
      find.byKey(const ValueKey('release.tokenField')),
      '  manual-token  ',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(repo.tokens, ['manual-token']);
    expect(repo.releases, 0);
  });

  testWidgets(
    'print failure keeps saved release and retry never releases again',
    (tester) async {
      final repo = _Repository();
      final printer = _Printer()..fail = true;
      final vm = await _pump(tester, repo, printer);
      await vm.verify('manual-token');
      await vm.release();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Print receipt'));
      await tester.tap(find.text('Print receipt'));
      await tester.pumpAndSettle();
      expect(find.textContaining('already recorded'), findsOneWidget);
      expect(vm.result, isNotNull);
      printer.fail = false;
      await tester.tap(find.text('Print receipt'));
      await tester.pumpAndSettle();
      expect(printer.receipts, hasLength(2));
      expect(repo.releases, 1);
    },
  );

  testWidgets('lookup failure shows retry rather than empty queue', (
    tester,
  ) async {
    final repo = _Repository()..offline = true;
    await _pump(tester, repo, _Printer());
    await tester.pumpAndSettle();
    expect(find.textContaining('Store offline'), findsWidgets);
    repo.offline = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('REQ-3'), findsOneWidget);
  });

  testWidgets('lookup and token controls fit narrow counter window', (
    tester,
  ) async {
    await _pump(tester, _Repository(), _Printer(), size: const Size(760, 900));
    await tester.pumpAndSettle();
    expect(find.text('REQ-3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
