// Phase 1d Task 10b (decisions 16-17): the purchase order details dialog joins
// the shared family, and adds the "Received x / y lines" summary.
//
// The summary counts LINES that have fully arrived, never sums: one line's
// quantity is in bags and another's in pieces, so adding them would be adding
// bags to pieces. A partly received line is named as such instead of rounding it
// up to "received".
//
// Copy pins kept from before: the variant name is the line's title (a live PO
// line carries no product name and no SKU), and a missing note reads "None",
// never a bare dash.

import 'dart:io';

import 'package:client/core/format/format.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/features/payables/widgets/supplier_return_dialog.dart';
import 'package:client/features/suppliers/widgets/purchases_details_dialog.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    ('OpenSans', ['OpenSans-Regular.ttf', 'OpenSans-Bold.ttf']),
    ('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(bytes.buffer.asByteData()));
    }
    await loader.load();
  }
}

/// Three lines in three different units: one fully arrived, one half arrived,
/// one not arrived at all. Summing the quantities would be nonsense.
PurchaseOrder _order({
  String notes = '',
  DateTime? expectedDelivery,
  String supplierName = 'Cebu Steel Works',
}) => PurchaseOrder(
  id: 41,
  supplierId: 9,
  supplierName: supplierName,
  orderDate: DateTime(2026, 10, 20),
  expectedDelivery: expectedDelivery,
  status: PurchaseStatus.partial,
  createdBy: 'Ana Lopez',
  notes: notes,
  items: const [
    PurchaseItem(
      productName: '',
      variantName: '40 kg bag',
      sku: '',
      quantity: 40,
      receivedQuantity: 40,
      unitCost: 285,
    ),
    PurchaseItem(
      productName: '',
      variantName: '10 mm x 6 m',
      sku: '',
      quantity: 120,
      receivedQuantity: 60,
      unitCost: 240,
    ),
    PurchaseItem(
      productName: '',
      variantName: 'PVC Pipe 2 in x 3 m',
      sku: '',
      quantity: 8,
      receivedQuantity: 0,
      unitCost: 320,
    ),
  ],
);

/// One processed delivery: two lines in two units, so a return has something to
/// offer and the receipt label has its own numbers to print.
GoodsReceiptRecord _receipt({
  int id = 5,
  DateTime? receiveDate,
}) => GoodsReceiptRecord(
  id: id,
  poId: 41,
  deliveryReceiptNo: 'DR-100$id',
  batches: const [],
  receiveDate: receiveDate ?? DateTime(2026, 11, 12),
  processedAt: DateTime(2026, 11, 12),
  lines: const [
    GoodsReceiptLine(id: 51, poItemId: 1, variantName: '40 kg bag', qty: 40),
    GoodsReceiptLine(id: 52, poItemId: 2, variantName: '10 mm x 6 m', qty: 60),
  ],
);

/// The return flow as the page wires it. [loadReturnable] and [submit] are never
/// reached from the PO details dialog itself, so they stay inert here.
SupplierReturnFlow _flow({
  List<GoodsReceiptRecord> receipts = const [],
  String? error,
  Future<SupplierReceiptsLoad> Function()? loadReceipts,
}) => SupplierReturnFlow(
  loadReceipts: loadReceipts ?? () async => (receipts: receipts, error: error),
  loadReturnable: (receiptId) async =>
      (lines: const <SupplierReturnableLine>[], error: null),
  submit: (request) async => (recorded: null, refusal: null),
);

void main() {
  setUpAll(_loadAppFonts);

  Future<FocusNode> open(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
    double scale = 1.0,
    PurchaseOrder? order,
    SupplierReturnFlow? flow,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.resetDevicePixelRatio);

    final opener = FocusNode(debugLabel: 'opener');
    addTearDown(opener.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: Focus(
              focusNode: opener,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => PurchasesDetailsDialog(
                      order: order ?? _order(),
                      returnFlow: flow,
                    ),
                  ),
                  child: const Text('Open PO'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    opener.requestFocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open PO'));
    await tester.pumpAndSettle();
    return opener;
  }

  testWidgets('the dialog is the shared shell with the order in its header', (
    tester,
  ) async {
    await open(tester);

    expect(find.byType(AppDialog), findsOneWidget);
    final title = tester.widget<Text>(find.text('PO-41'));
    expect(title.style?.fontFamily, 'Cinzel');
    expect(title.style!.fontSize!, greaterThanOrEqualTo(18));
    expect(find.byType(HexIconBadge), findsOneWidget);
    // Supplier as the subtitle, its status as the header pill.
    expect(find.text('Cebu Steel Works'), findsOneWidget);
    expect(find.text('Partially Received'), findsOneWidget);

    expect(find.text('ORDER'), findsOneWidget);
    expect(find.byType(DetailRow), findsWidgets);
    expect(find.text('Created by'), findsOneWidget);
    expect(find.text('Ana Lopez'), findsOneWidget);
    // D18: no bare dash for "no value".
    expect(find.text('None'), findsOneWidget);
    expect(find.textContaining('—'), findsNothing);
  });

  testWidgets('the summary counts fully received lines, not summed units', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Received 1 / 3 lines'), findsOneWidget);
    // A line that is half here says so, and says how much is here. The caption is
    // one line of text: the ordered quantity, then what has arrived.
    expect(find.text('Ordered 120 · Received 60 of 120'), findsOneWidget);
    expect(find.text('Ordered 8 · Received 0 of 8'), findsOneWidget);
    expect(find.text('Ordered 40 · Received 40'), findsOneWidget);
    expect(
      find.text('A line counts as received only when all of it has arrived.'),
      findsOneWidget,
      reason: 'a partial line must not be rounded up to received',
    );
  });

  testWidgets('an order with nothing received explains the summary too', (
    tester,
  ) async {
    final order = PurchaseOrder(
      id: 43,
      supplierId: 9,
      supplierName: 'Cebu Steel Works',
      orderDate: DateTime(2026, 10, 18),
      expectedDelivery: null,
      status: PurchaseStatus.draft,
      createdBy: 'Ana Lopez',
      notes: '',
      items: const [
        PurchaseItem(
          productName: '',
          variantName: '40 kg bag',
          sku: '',
          quantity: 50,
          receivedQuantity: 0,
          unitCost: 285,
        ),
      ],
    );
    await open(tester, order: order);

    expect(find.text('Received 0 / 1 lines'), findsOneWidget);
    // A short order has no partly received line, so the sentence that explains
    // partials is not shown.
    expect(
      find.text('A line counts as received only when all of it has arrived.'),
      findsNothing,
    );
  });

  testWidgets('money: per line subtotal, and the total in the gold bar', (
    tester,
  ) async {
    final order = _order();
    await open(tester, order: order);

    expect(find.text(formatPeso(40 * 285)), findsOneWidget);
    final bar = tester.widget<TotalBar>(find.byType(TotalBar));
    expect(bar.label, 'Order total');
    expect(
      bar.amount,
      order.total,
      reason: 'the bar formats a number, so a total cannot drift',
    );
    expect(find.text(formatPeso(order.total)), findsOneWidget);
  });

  testWidgets('a missing expected delivery reads "Not set", never a dash', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Expected delivery'), findsOneWidget);
    expect(find.text('Not set'), findsOneWidget);
    expect(find.textContaining('—'), findsNothing);
    expect(find.text(formatDate(DateTime(2026, 10, 20))), findsOneWidget);
  });

  testWidgets('Esc closes and focus returns to the button that opened it', (
    tester,
  ) async {
    final opener = await open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(opener.hasPrimaryFocus, isTrue);
  });

  // Phase 8 F2: "Return to supplier" is offered only where it can work — an
  // order whose delivery the server has processed into batches. A receipt that
  // was never processed created no stock, so a return off it would 400.
  testWidgets('a processed delivery raises the return control', (tester) async {
    await open(tester, flow: _flow(receipts: [_receipt()]));

    expect(find.text('Return to supplier'), findsOneWidget);
    expect(
      find.text('1 processed delivery can still give goods back.'),
      findsOneWidget,
    );
  });

  testWidgets('an order with no processed delivery offers no return', (
    tester,
  ) async {
    await open(tester, flow: _flow());

    expect(find.text('Return to supplier'), findsNothing);
    expect(
      find.text('No processed deliveries to return from.'),
      findsOneWidget,
      reason: 'the absence must be explained, not silently empty',
    );
  });

  testWidgets('without a wired flow the dialog is exactly as before', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('Return to supplier'), findsNothing);
    expect(find.text('No processed deliveries to return from.'), findsNothing);
  });

  testWidgets('a failed delivery load is named, with a retry', (tester) async {
    var calls = 0;
    final flow = _flow(
      loadReceipts: () async {
        calls++;
        return calls == 1
            ? (
                receipts: const <GoodsReceiptRecord>[],
                error: 'The goods receipts could not be read.',
              )
            : (receipts: [_receipt()], error: null);
      },
    );
    await open(tester, flow: flow);

    expect(find.text('The goods receipts could not be read.'), findsOneWidget);
    expect(
      find.text('Return to supplier'),
      findsNothing,
      reason: 'an unread delivery list cannot say whether a return is possible',
    );

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Return to supplier'), findsOneWidget);
  });

  testWidgets('the control opens the return dialog on this order', (
    tester,
  ) async {
    await open(tester, flow: _flow(receipts: [_receipt()]));

    await tester.tap(find.text('Return to supplier'));
    await tester.pumpAndSettle();

    expect(find.byType(SupplierReturnDialog), findsOneWidget);
    expect(find.text('PO-41 · Cebu Steel Works'), findsOneWidget);
  });

  testWidgets('the return section fits 760 px at 1.3x text', (tester) async {
    await open(
      tester,
      size: const Size(760, 1000),
      scale: 1.3,
      flow: _flow(receipts: [_receipt()]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Return to supplier').hitTestable(), findsOneWidget);
    final rect = tester.getRect(find.byType(AppDialog));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(760));
  });

  for (final (width, scale) in const [
    (1440.0, 1.0),
    (1100.0, 1.0),
    (760.0, 1.3),
  ]) {
    testWidgets('lays out at ${width.toInt()} px, text scale $scale', (
      tester,
    ) async {
      await open(
        tester,
        size: Size(width, 1000),
        scale: scale,
        order: _order(
          notes:
              'Second delivery expected. Call the supplier the day before the '
              'truck leaves Mandaue so the gate is open.',
          expectedDelivery: DateTime(2026, 10, 25),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Received 1 / 3 lines'), findsOneWidget);
      expect(find.byType(TotalBar), findsOneWidget);
      expect(find.text('Close').hitTestable(), findsOneWidget);
      final rect = tester.getRect(find.byType(AppDialog));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(width));
    });
  }
}
