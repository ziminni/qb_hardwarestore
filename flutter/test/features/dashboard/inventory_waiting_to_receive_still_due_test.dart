// F1 review: "Still due" summed ordered-minus-received across every line and
// labelled the total with one unit code. Two BAG packages (25 kg and 40 kg) are
// not one BAG count, and BAG plus KG is not fourteen of anything. The fix counts
// the OPEN lines instead, the same progress wording Phase 1d already uses, and
// only names a quantity when a single line owns it.
//
// RED first: these fail against the old sum-and-label cell.

import 'dart:io';

import 'package:client/data/models/supplier.dart';
import 'package:client/features/dashboard/widget/inventory_waiting_to_receive_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PurchaseItem _line({
  required double ordered,
  required double received,
  String uomCode = '',
  String variantName = 'Portland Cement',
}) => PurchaseItem(
  productName: '',
  variantName: variantName,
  sku: '',
  quantity: ordered,
  receivedQuantity: received,
  unitCost: 240,
  uomCode: uomCode,
);

PurchaseOrder _order(int id, List<PurchaseItem> items) => PurchaseOrder(
  id: id,
  supplierId: 1,
  supplierName: 'Cebu Hardware Trading',
  orderDate: DateTime(2026, 10, 20),
  expectedDelivery: null,
  status: PurchaseStatus.partial,
  createdBy: 'Ana Lopez',
  notes: '',
  items: items,
);

Future<void> _pump(
  WidgetTester tester,
  List<PurchaseOrder> orders, {
  double width = 1200,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: InventoryWaitingToReceivePanel(
              orders: orders,
              total: orders.length,
              emptyMessage: 'Nothing waiting',
              onViewAll: () {},
              onRowTap: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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

void main() {
  testWidgets('two BAG lines of different box sizes count lines, not a sum', (
    tester,
  ) async {
    await _pump(tester, [
      _order(1, [
        _line(
          ordered: 10,
          received: 4,
          uomCode: 'BAG',
          variantName: 'Portland Cement 25kg',
        ),
        _line(
          ordered: 8,
          received: 3,
          uomCode: 'BAG',
          variantName: 'Portland Cement 40kg',
        ),
      ]),
    ]);

    // 6 and 5 remain on two different box sizes: "11 BAG" would be a lie even
    // though both lines carry the same unit code.
    expect(find.text('2 lines remaining'), findsOneWidget);
    expect(find.text('11 BAG'), findsNothing);
    expect(find.text('11'), findsNothing);
  });

  testWidgets('BAG plus KG stays a line count, never a bare sum', (
    tester,
  ) async {
    await _pump(tester, [
      _order(2, [
        _line(ordered: 10, received: 0, uomCode: 'BAG'),
        _line(ordered: 5, received: 0, uomCode: 'KG'),
      ]),
    ]);

    expect(find.text('2 lines remaining'), findsOneWidget);
    expect(find.text('15'), findsNothing);
  });

  testWidgets(
    'a fully received sibling is excluded and the one line is named',
    (tester) async {
      await _pump(tester, [
        _order(3, [
          _line(ordered: 10, received: 10, uomCode: 'BAG'),
          _line(ordered: 60, received: 0, uomCode: 'KG'),
        ]),
      ]);

      // One open line, so its own quantity and unit are honest to show.
      expect(find.text('60 KG'), findsOneWidget);
      expect(find.text('1 lines remaining'), findsNothing);
    },
  );

  testWidgets(
    'an old-wire line with no unit code still shows the plain count',
    (tester) async {
      await _pump(tester, [
        _order(4, [_line(ordered: 100, received: 40)]),
      ]);

      expect(find.text('60'), findsOneWidget);
    },
  );

  testWidgets('nothing open reads a truthful zero, not a unit word', (
    tester,
  ) async {
    await _pump(tester, [
      _order(5, [_line(ordered: 10, received: 10, uomCode: 'BAG')]),
    ]);

    expect(find.text('0'), findsOneWidget);
    expect(find.text('0 lines remaining'), findsNothing);
    expect(find.text('0 BAG'), findsNothing);
  });

  testWidgets('the line count fits at the narrow end of the table layout', (
    tester,
  ) async {
    // Real file I/O inside testWidgets needs runAsync: the test binding's fake
    // clock never advances a real read, so a plain await hangs forever.
    await tester.runAsync(_loadAppFonts);
    // 740 is just above the 720 breakpoint, so the table paints its tightest
    // real-font column rather than switching to cards.
    await _pump(tester, [
      _order(6, [
        _line(ordered: 10, received: 4, uomCode: 'BAG'),
        _line(ordered: 8, received: 3, uomCode: 'KG'),
      ]),
    ], width: 740);

    expect(find.text('2 lines remaining'), findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('2 lines remaining'),
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'the line count must not ellipsize in its own column',
    );
  });
}
