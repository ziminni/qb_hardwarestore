// Phase 8 F3 (decision 20 #1): the credit-notes tab.
//
// Pinned here:
//   * the number, what it was worth and WHAT IS LEFT are three columns, because
//     "remaining" is the only figure a manager spends;
//   * a supplier filter narrows the list; nothing is hidden by default;
//   * an empty list says a note is written by a return, not by anything the
//     reader can do on this tab.

import 'dart:io';

import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/data/repositories/payables_repository.dart';
import 'package:client/data/services/payables_service.dart';
import 'package:client/features/payables/viewmodels/payables_viewmodel.dart';
import 'package:client/features/payables/widgets/supplier_credit_notes_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

SupplierCreditNote _note({
  int id = 12,
  String number = 'CN-20261113-0001',
  int supplierId = 2,
  double total = 300,
  double remaining = 200,
}) => SupplierCreditNote(
  id: id,
  number: number,
  supplierId: supplierId,
  supplierName: supplierId == 2 ? 'Cebu Steel Works' : 'Bohol Lumber',
  supplierReturnId: 3,
  sourceBillId: 4,
  value: 267.86,
  vatRate: 12,
  vatInclusive: true,
  vatAmount: 32.14,
  totalAmount: total,
  remainingAmount: remaining,
  appliedAmount: total - remaining,
  createdAt: DateTime(2026, 11, 13),
);

class _StubRepository extends PayablesRepository {
  _StubRepository({List<SupplierCreditNote>? notes})
    : notes = notes ?? [_note()];

  List<SupplierCreditNote> notes;
  String? failure;

  @override
  Future<List<SupplierBill>> fetchBills({
    int? supplierId,
    SupplierBillStatus? status,
    bool overdueOnly = false,
  }) async => const [];

  @override
  Future<List<SupplierPayable>> fetchSummary() async => const [];

  @override
  Future<List<SupplierCreditNote>> fetchCreditNotes({
    int? supplierId,
    bool openOnly = false,
  }) async {
    if (failure != null) throw PayablesServiceException(failure!);
    return notes;
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
  _StubRepository repository, {
  int? supplierId,
  Size size = const Size(1400, 900),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<PayablesViewmodel>.value(
      value: PayablesViewmodel(repository: repository),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: SupplierCreditNotesTab(supplierId: supplierId)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('a note shows its number, what it was worth and what is left', (
    tester,
  ) async {
    await _pump(tester, _StubRepository());

    expect(find.text('CN-20261113-0001'), findsOneWidget);
    expect(find.text('Cebu Steel Works'), findsWidgets);
    expect(find.text(formatPeso(300)), findsOneWidget, reason: 'total');
    expect(find.text(formatPeso(100)), findsOneWidget, reason: 'applied');
    expect(find.text(formatPeso(200)), findsOneWidget, reason: 'remaining');
  });

  testWidgets('the supplier filter narrows the list', (tester) async {
    await _pump(
      tester,
      _StubRepository(
        notes: [
          _note(id: 12, number: 'CN-20261113-0001'),
          _note(id: 14, number: 'CN-20261113-0002', supplierId: 3),
        ],
      ),
      supplierId: 3,
    );

    expect(find.text('CN-20261113-0002'), findsOneWidget);
    expect(find.text('CN-20261113-0001'), findsNothing);
  });

  testWidgets('no notes says where a note comes from', (tester) async {
    await _pump(tester, _StubRepository(notes: const []));

    expect(find.textContaining('No supplier credit notes yet'), findsOneWidget);
  });

  testWidgets('a failed read is a retryable banner, not an empty list', (
    tester,
  ) async {
    await _pump(tester, _StubRepository()..failure = 'Credit is down.');

    expect(find.text('Credit is down.'), findsOneWidget);
  });

  testWidgets('760 px at 1.3x text, the notes render whole', (tester) async {
    await _pump(
      tester,
      _StubRepository(),
      size: const Size(760, 900),
      scale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('CN-20261113-0001'), findsOneWidget);
  });
}
