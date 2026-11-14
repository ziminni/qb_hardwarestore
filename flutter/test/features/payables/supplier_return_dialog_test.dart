// Phase 8 F2 (decision 20): the return-to-supplier dialog.
//
// Pinned here, because each one is a wire fact rather than taste:
//   * the dialog opens on a RECEIPT, because a return takes stock off that
//     delivery's own batches — never off "the variant" at large;
//   * every quantity is offered and sent in the receipt LINE's package unit
//     (a BAG line answers in bags), never converted to base units by the client;
//   * a line that can give nothing back is not offered, and a clerk is never
//     asked to type a zero;
//   * only lines with a quantity are sent, as 2 dp strings: the server refuses a
//     fraction of a whole package unit and a bare double could send
//     `2.0000000000000004`;
//   * a refusal is shown in the server's own sentence, with every typed value
//     still in place, because retyping a whole return to fix one line is how
//     double returns happen;
//   * the button posts once — the stock and the credit note are real at that
//     point;
//   * the answer names the credit note, what the bill absorbed and what stays as
//     supplier credit, which is what the clerk writes on the supplier's copy;
//   * at 760 px with 1.3x text nothing clips.

import 'dart:async';
import 'dart:io';

import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/features/payables/widgets/supplier_return_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

GoodsReceiptRecord _receipt({
  int id = 5,
  int poId = 41,
  String deliveryReceiptNo = 'DR-1001',
  DateTime? receiveDate,
  DateTime? processedAt,
  int lines = 2,
}) => GoodsReceiptRecord(
  id: id,
  poId: poId,
  deliveryReceiptNo: deliveryReceiptNo,
  batches: const [],
  receiveDate: receiveDate ?? DateTime(2026, 11, 12),
  processedAt: processedAt ?? DateTime(2026, 11, 12),
  lines: [
    for (var i = 0; i < lines; i++)
      GoodsReceiptLine(
        id: id * 10 + i,
        poItemId: i + 1,
        variantName: 'Portland Cement 40kg',
        qty: 10,
      ),
  ],
);

SupplierReturnableLine _returnable({
  int receiptLineId = 11,
  String name = 'Portland Cement 40kg',
  String unit = 'BAG',
  double delivered = 10,
  double returned = 0,
  double returnable = 3,
}) => SupplierReturnableLine(
  receiptLineId: receiptLineId,
  variantId: receiptLineId + 100,
  variantName: name,
  unit: unit,
  delivered: delivered,
  returned: returned,
  returnable: returnable,
);

/// One batch, one line, one hundred pesos of cement.
SupplierReturn _recorded({
  int? billId = 12,
  double total = 300,
  double remaining = 100,
  String? number = 'CN-20261114-0001',
}) => SupplierReturn(
  id: 7,
  receiptId: 5,
  supplierId: 2,
  supplierName: 'Cebu Steel Works',
  purchaseOrderId: 41,
  billId: billId,
  reason: 'Damaged in transit',
  createdByName: 'Ana Lopez',
  createdAt: DateTime(2026, 11, 14),
  creditNoteNumber: number,
  creditNoteTotal: total,
  creditNoteRemaining: remaining,
  lines: const [],
);

/// What the dialog asked the viewmodel for, and what it was told back.
class _Wire {
  final List<int> loadedReceipts = [];
  final List<SupplierReturnRequest> submitted = [];
  Map<int, List<SupplierReturnableLine>> lines = {};
  String? loadFailure;
  ({SupplierReturn? recorded, String? refusal}) outcome = (
    recorded: null,
    refusal: null,
  );
  Completer<void>? hold;
}

Future<_Wire> _open(
  WidgetTester tester, {
  List<GoodsReceiptRecord>? receipts,
  _Wire? wire,
  Size size = const Size(1440, 1000),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetDevicePixelRatio);

  final state = wire ?? _Wire();
  final deliveries = receipts ?? [_receipt()];

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<bool>(
              context: context,
              builder: (_) => SupplierReturnDialog(
                receipts: deliveries,
                supplierName: 'Cebu Steel Works',
                purchaseOrderId: 41,
                flow: SupplierReturnFlow(
                  // The dialog takes its receipts as a constructor argument, so
                  // this one is only part of the flow object the PO details
                  // dialog uses.
                  loadReceipts: () async =>
                      (receipts: const <GoodsReceiptRecord>[], error: null),
                  loadReturnable: (receiptId) async {
                    state.loadedReceipts.add(receiptId);
                    final failure = state.loadFailure;
                    if (failure != null) {
                      return (
                        lines: const <SupplierReturnableLine>[],
                        error: failure,
                      );
                    }
                    return (
                      lines: state.lines[receiptId] ?? [_returnable()],
                      error: null,
                    );
                  },
                  submit: (request) async {
                    state.submitted.add(request);
                    final hold = state.hold;
                    if (hold != null) await hold.future;
                    return state.outcome;
                  },
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return state;
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

String? _fieldText(WidgetTester tester, Key key) =>
    tester.widget<TextFormField>(find.byKey(key)).controller?.text;

void main() {
  setUpAll(_loadAppFonts);

  testWidgets(
    'it opens on the first receipt and asks for its returnable lines',
    (tester) async {
      final wire = await _open(tester);

      expect(find.text('Return to supplier'), findsOneWidget);
      expect(wire.loadedReceipts, [5]);
      // The quantity is offered in the LINE's package unit, with what is left.
      expect(find.text('Returnable 3 BAG of 10 delivered'), findsOneWidget);
      expect(find.byKey(const ValueKey('return-qty-11')), findsOneWidget);
    },
  );

  testWidgets('picking another receipt loads that receipt\'s own lines', (
    tester,
  ) async {
    final wire = _Wire();
    wire.lines[5] = [_returnable()];
    wire.lines[6] = [
      _returnable(
        receiptLineId: 21,
        name: 'PVC Pipe 2 in x 3 m',
        unit: 'PC',
        delivered: 8,
        returnable: 5,
      ),
    ];
    await _open(
      tester,
      wire: wire,
      receipts: [
        _receipt(),
        _receipt(id: 6, deliveryReceiptNo: 'DR-1002', lines: 1),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('return-receipt')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DR-1002 · Nov 12, 2026 · 1 line').last);
    await tester.pumpAndSettle();

    expect(wire.loadedReceipts, [5, 6]);
    expect(find.text('Returnable 5 PC of 8 delivered'), findsOneWidget);
    expect(find.byKey(const ValueKey('return-qty-21')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('return-qty-11')),
      findsNothing,
      reason: 'the first receipt\'s line must not linger under the second',
    );
  });

  testWidgets('a line that can give nothing back is not offered', (
    tester,
  ) async {
    final wire = _Wire();
    wire.lines[5] = [
      _returnable(receiptLineId: 11, returnable: 0, delivered: 10),
      _returnable(receiptLineId: 12, name: 'PVC Pipe 2 in x 3 m', unit: 'PC'),
    ];
    await _open(tester, wire: wire);

    expect(
      find.byKey(const ValueKey('return-qty-11')),
      findsNothing,
      reason: 'a sold-down line has nothing to send back',
    );
    expect(find.byKey(const ValueKey('return-qty-12')), findsOneWidget);
  });

  testWidgets('a delivery with nothing returnable says so', (tester) async {
    final wire = _Wire();
    wire.lines[5] = [_returnable(returnable: 0)];
    await _open(tester, wire: wire);

    expect(find.text('Nothing on this delivery can go back.'), findsOneWidget);
    expect(find.byKey(const ValueKey('return-submit')), findsNothing);
  });

  testWidgets('the typed quantity and reason reach the wire as asked', (
    tester,
  ) async {
    final wire = await _open(tester);

    await tester.enterText(find.byKey(const ValueKey('return-qty-11')), '2');
    await tester.enterText(
      find.byKey(const ValueKey('return-reason')),
      'Damaged in transit',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('return-submit')));
    await tester.pumpAndSettle();

    expect(wire.submitted, hasLength(1));
    final request = wire.submitted.single;
    expect(request.receiptId, 5);
    expect(request.reason, 'Damaged in transit');
    expect(request.lines, hasLength(1));
    expect(request.lines.single.receiptLineId, 11);
    expect(request.lines.single.qty, 2);
  });

  testWidgets('a line left blank is not part of the return', (tester) async {
    final wire = _Wire();
    wire.lines[5] = [
      _returnable(receiptLineId: 11),
      _returnable(receiptLineId: 12, name: 'PVC Pipe 2 in x 3 m', unit: 'PC'),
    ];
    await _open(tester, wire: wire);

    await tester.enterText(find.byKey(const ValueKey('return-qty-12')), '2');
    await tester.enterText(
      find.byKey(const ValueKey('return-reason')),
      'Wrong size',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('return-submit')));
    await tester.pumpAndSettle();

    expect(wire.submitted.single.lines, hasLength(1));
    expect(wire.submitted.single.lines.single.receiptLineId, 12);
    expect(wire.submitted.single.lines.single.qty, 2);
  });

  testWidgets('a return with no quantity is refused before the round trip', (
    tester,
  ) async {
    final wire = await _open(tester);

    await tester.enterText(
      find.byKey(const ValueKey('return-reason')),
      'Damaged in transit',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('return-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a quantity for at least one line.'),
      findsOneWidget,
    );
    expect(wire.submitted, isEmpty);
  });

  testWidgets('a reason is required, and says why in words', (tester) async {
    final wire = await _open(tester);

    await tester.enterText(find.byKey(const ValueKey('return-qty-11')), '1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('return-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Say why the goods are going back.'), findsOneWidget);
    expect(wire.submitted, isEmpty);
  });

  testWidgets('more than the delivery can give back is refused in place', (
    tester,
  ) async {
    final wire = await _open(tester);

    await tester.enterText(find.byKey(const ValueKey('return-qty-11')), '4');
    await tester.enterText(
      find.byKey(const ValueKey('return-reason')),
      'Damaged in transit',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('return-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Only 3 BAG can go back on this line.'), findsOneWidget);
    expect(wire.submitted, isEmpty);
  });

  testWidgets('a server refusal keeps every typed value in place', (
    tester,
  ) async {
    final wire = _Wire();
    wire.outcome = (
      recorded: null,
      refusal: 'RETURN_EXCEEDS_RECEIPT: only 2.00 BAG left on this line.',
    );
    await _open(tester, wire: wire);

    await tester.enterText(find.byKey(const ValueKey('return-qty-11')), '2');
    await tester.enterText(
      find.byKey(const ValueKey('return-reason')),
      'Damaged in transit',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('return-submit')));
    await tester.pumpAndSettle();

    expect(
      find.text('RETURN_EXCEEDS_RECEIPT: only 2.00 BAG left on this line.'),
      findsOneWidget,
    );
    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(_fieldText(tester, const ValueKey('return-qty-11')), '2');
    expect(
      _fieldText(tester, const ValueKey('return-reason')),
      'Damaged in transit',
    );

    // And it can be submitted again without leaving the dialog.
    wire.outcome = (recorded: _recorded(), refusal: null);
    await tester.tap(find.byKey(const ValueKey('return-submit')));
    await tester.pumpAndSettle();
    expect(wire.submitted, hasLength(2));
    expect(find.text('CN-20261114-0001'), findsOneWidget);
  });

  testWidgets('the button posts once while the request is in flight', (
    tester,
  ) async {
    final wire = _Wire()..hold = Completer<void>();
    await _open(tester, wire: wire);

    await tester.enterText(find.byKey(const ValueKey('return-qty-11')), '1');
    await tester.enterText(
      find.byKey(const ValueKey('return-reason')),
      'Damaged in transit',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('return-submit')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('return-submit')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(
      wire.submitted,
      hasLength(1),
      reason: 'a second tap would move the same stock and mint a second note',
    );

    wire.outcome = (recorded: _recorded(), refusal: null);
    wire.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('CN-20261114-0001'), findsOneWidget);
  });

  testWidgets(
    'the answer names the note, the bill it settled and the credit left',
    (tester) async {
      final wire = _Wire()..outcome = (recorded: _recorded(), refusal: null);
      await _open(tester, wire: wire);

      await tester.enterText(find.byKey(const ValueKey('return-qty-11')), '3');
      await tester.enterText(
        find.byKey(const ValueKey('return-reason')),
        'Damaged in transit',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('return-submit')));
      await tester.pumpAndSettle();

      expect(find.text('CREDIT NOTE'), findsOneWidget);
      expect(find.text('CN-20261114-0001'), findsOneWidget);
      expect(find.text('Bill #12 · ${formatPeso(200)}'), findsOneWidget);
      expect(find.text('Left as credit'), findsOneWidget);
      expect(find.text(formatPeso(100)), findsOneWidget);
      // The form is gone: the return is written, so there is nothing left to edit.
      expect(find.byKey(const ValueKey('return-qty-11')), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(SupplierReturnDialog), findsNothing);
    },
  );

  testWidgets('a delivery with no bill leaves the whole note as credit', (
    tester,
  ) async {
    final wire = _Wire()
      ..outcome = (
        recorded: _recorded(billId: null, total: 300, remaining: 300),
        refusal: null,
      );
    await _open(tester, wire: wire);

    await tester.enterText(find.byKey(const ValueKey('return-qty-11')), '3');
    await tester.enterText(
      find.byKey(const ValueKey('return-reason')),
      'Damaged in transit',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('return-submit')));
    await tester.pumpAndSettle();

    expect(find.text('No bill for this delivery'), findsOneWidget);
    // Credited and left as credit are both the whole 300: nothing was applied.
    expect(find.text(formatPeso(300)), findsNWidgets(2));
  });

  testWidgets('a failed load says so and offers the retry', (tester) async {
    final wire = _Wire()
      ..loadFailure = 'The returnable quantities could not be loaded.';
    await _open(tester, wire: wire);

    expect(
      find.text('The returnable quantities could not be loaded.'),
      findsOneWidget,
    );

    wire.loadFailure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(wire.loadedReceipts, [5, 5]);
    expect(find.byKey(const ValueKey('return-qty-11')), findsOneWidget);
  });

  for (final (width, scale) in const [(1440.0, 1.0), (760.0, 1.3)]) {
    testWidgets(
      'lays out at ${width.toInt()} px, text scale $scale, refusal included',
      (tester) async {
        final wire = _Wire()
          ..outcome = (
            recorded: null,
            refusal:
                'RETURN_EXCEEDS_RECEIPT: only 2.00 BAG left on this line, so '
                '3.00 cannot go back.',
          );
        await _open(tester, wire: wire, size: Size(width, 1000), scale: scale);

        await tester.enterText(
          find.byKey(const ValueKey('return-qty-11')),
          '2',
        );
        await tester.enterText(
          find.byKey(const ValueKey('return-reason')),
          'Damaged in transit',
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('return-submit')));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final refusal = find.text(
          'RETURN_EXCEEDS_RECEIPT: only 2.00 BAG left on this line, so '
          '3.00 cannot go back.',
        );
        expect(refusal, findsOneWidget);
        expect(
          tester.renderObject<RenderParagraph>(refusal).didExceedMaxLines,
          isFalse,
          reason: 'a clipped refusal cannot be acted on',
        );
        final rect = tester.getRect(find.byType(SupplierReturnDialog));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(find.text('Record return').hitTestable(), findsOneWidget);
      },
    );
  }
}
