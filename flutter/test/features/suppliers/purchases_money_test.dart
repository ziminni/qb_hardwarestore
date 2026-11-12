// Phase 5 F2 (decision 18): money on a purchase order.
//
// The server owns the figures: `discount_amount` caps the discount at the gross
// (`INVALID_PO`), `vat_inclusive` decides the split, and the read-only totals
// arrive computed. Pinned here:
//   * the form sends both controls, and refuses a discount above the gross
//     before the round trip (with a sentence, not a red field);
//   * the details dialog shows the SERVER's gross/discount/net/VATable/VAT/total
//     even when they disagree with the lines it can see;
//   * a pre-B2 order (no totals on the wire) keeps the line-sum total it always
//     had, and invents no VAT.

import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/suppliers/widgets/purchases_details_dialog.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

Map<String, dynamic> _orderJson({
  bool withMoney = true,
  bool withVatRate = true,
  bool withVatAmount = true,
}) => {
  'id': 41,
  'supplier': 9,
  'created_by': 3,
  'created_by_name': 'Ana Lopez',
  'order_date': '2026-10-19',
  'expected_delivery': null,
  'status': 'DRAFT',
  'notes': '',
  'items': [
    {
      'id': 11,
      'po': 41,
      'variant': 8,
      'variant_name': 'Portland 40kg',
      'ordered_qty': '10.00',
      'unit_cost': '120.00',
      'received_qty': '0.00',
    },
  ],
  if (withMoney) ...{
    'discount_amount': '100.00',
    'vat_inclusive': true,
    if (withVatRate) 'vat_rate': '12.00',
    'gross_amount': '1200.00',
    'net_amount': '1100.00',
    'vatable_amount': '982.14',
    if (withVatAmount) 'vat_amount': '117.86',
    'total_amount': '1100.00',
  },
};

Future<void> _loadAppFonts() async {}

Future<void> _size(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

class _ResultBox {
  PurchaseOrderFormResult? value;
}

Future<_ResultBox> _pumpForm(WidgetTester tester) async {
  await _size(tester, const Size(1400, 1200));
  final box = _ResultBox();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              box.value = await showDialog<PurchaseOrderFormResult>(
                context: context,
                builder: (_) => PurchasesFormDialog(
                  suppliers: [
                    Supplier(
                      id: 9,
                      companyName: 'Cebu Steel Works',
                      contactPerson: '',
                      phone: '',
                      email: '',
                      address: '',
                      isActive: true,
                    ),
                  ],
                  products: [
                    product(
                      id: 6,
                      name: 'Portland Cement',
                      variants: [
                        variant(
                          id: 8,
                          productId: 6,
                          name: 'Portland 40kg',
                          baseUomCode: 'KG',
                        ),
                      ],
                    ),
                  ],
                  costFor: (_) => 120,
                  initialVariantId: 8,
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return box;
}

void main() {
  setUpAll(_loadAppFonts);

  group('PurchaseOrder money on the wire', () {
    test('a payload carries the discount and the VAT flag', () {
      final order = PurchaseOrder.fromJson(_orderJson());

      expect(order.discountAmount, 100);
      expect(order.vatInclusive, isTrue);
      expect(order.vatRate, 12);
      expect(order.grossAmount, 1200);
      expect(order.netAmount, 1100);
      expect(order.vatableAmount, 982.14);
      expect(order.vatAmount, 117.86);
      expect(order.serverTotalAmount, 1100);
      expect(order.hasServerTotals, isTrue);
    });

    test('a pre-B2 order has no server totals and keeps its line sum', () {
      final order = PurchaseOrder.fromJson(_orderJson(withMoney: false));

      expect(order.hasServerTotals, isFalse);
      expect(order.discountAmount, 0);
      expect(order.vatRate, isNull);
      // 10 x 120: the only truth such a payload carries.
      expect(order.total, 1200);
      expect(order.displayTotal, 1200);
    });

    test('the server total wins over the line sum', () {
      final order = PurchaseOrder.fromJson(_orderJson());

      expect(order.total, 1200, reason: 'the lines say 10 x 120');
      expect(order.displayTotal, 1100, reason: 'the server says what it is');
    });
  });

  group('the form', () {
    testWidgets('sends the discount and the VAT flag', (tester) async {
      final box = await _pumpForm(tester);

      await tester.enterText(find.byKey(const ValueKey('po-discount')), '100');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('po-vat-inclusive')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();

      final json = box.value!.draft.toJson();
      expect(json['discount_amount'], '100.00');
      expect(json['vat_inclusive'], isFalse);
    });

    testWidgets('a discount above the gross is refused with a sentence', (
      tester,
    ) async {
      final box = await _pumpForm(tester);

      await tester.enterText(find.byKey(const ValueKey('po-discount')), '5000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('cannot be more than the order total'),
        findsOneWidget,
      );
      expect(box.value, isNull, reason: 'a refused form must not pop a draft');
    });

    testWidgets('the preview shows gross, discount and net', (tester) async {
      await _pumpForm(tester);

      // 1 x 120 at the prefilled cost.
      expect(find.text('Gross'), findsOneWidget);
      expect(find.text(formatPeso(120)), findsWidgets);

      await tester.enterText(find.byKey(const ValueKey('po-discount')), '20');
      await tester.pumpAndSettle();

      expect(find.text('Net'), findsOneWidget);
      expect(find.text(formatPeso(100)), findsWidgets);
    });
  });

  group('the details dialog', () {
    testWidgets('shows the server figures', (tester) async {
      await _size(tester, const Size(1400, 1100));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: PurchasesDetailsDialog(
            order: PurchaseOrder.fromJson(_orderJson()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gross'), findsOneWidget);
      expect(find.text(formatPeso(1200)), findsWidgets);
      expect(find.text('Discount'), findsOneWidget);
      expect(find.text(formatPeso(100)), findsOneWidget);
      expect(find.text('VATable'), findsOneWidget);
      expect(find.text(formatPeso(982.14)), findsOneWidget);
      expect(find.text('VAT (12%)'), findsOneWidget);
      expect(find.text(formatPeso(117.86)), findsOneWidget);
      expect(find.text(formatPeso(1100)), findsWidgets);
    });

    // Item 9: server totals can arrive without the rate snapshot. The row is
    // still VAT; only the rate nobody sent is dropped — no zero rate, no zero
    // tax invented to stand in for it.
    testWidgets('a total without a VAT rate shows VAT, not an invented rate', (
      tester,
    ) async {
      await _size(tester, const Size(1400, 1100));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: PurchasesDetailsDialog(
            order: PurchaseOrder.fromJson(_orderJson(withVatRate: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('VAT'), findsOneWidget);
      expect(find.textContaining('VAT ('), findsNothing);
      expect(
        find.text('Not VAT registered'),
        findsNothing,
        reason: 'a missing rate is not a 0% shop',
      );
      expect(
        find.text(formatPeso(117.86)),
        findsOneWidget,
        reason: 'the tax the server did send is still shown',
      );
    });

    testWidgets('a total without a VAT rate or amount says so, never ₱0.00', (
      tester,
    ) async {
      await _size(tester, const Size(1400, 1100));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: PurchasesDetailsDialog(
            order: PurchaseOrder.fromJson(
              _orderJson(withVatRate: false, withVatAmount: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('VAT'), findsOneWidget);
      expect(find.text('Not recorded'), findsOneWidget);
      expect(
        find.text(formatPeso(0)),
        findsNothing,
        reason: 'a zero would claim the order holds no tax',
      );
    });

    testWidgets('a pre-B2 order keeps the plain total bar', (tester) async {
      await _size(tester, const Size(1400, 1100));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: PurchasesDetailsDialog(
            order: PurchaseOrder.fromJson(_orderJson(withMoney: false)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Gross'), findsNothing);
      // TotalBar upper-cases its own label.
      expect(find.text('ORDER TOTAL'), findsOneWidget);
      expect(find.text(formatPeso(1200)), findsWidgets);
    });
  });
}
