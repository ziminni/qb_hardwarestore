// Phase 5 F3 follow-up: the create-only sales order form (owner-authorised).
//
// What this file pins, and why each one is a wire contract rather than taste:
//   * the body it POSTs — customer, lines in the SELLING unit, optional delivery,
//     and NO `status` (the server defaults CONFIRMED);
//   * a whole unit is refused HERE, before a request the server would answer with
//     WHOLE_UNIT_QUANTITY, and a fee with three decimals is refused the same way
//     (the server refuses 10.005 rather than rounding it);
//   * a server refusal keeps the dialog OPEN with every input intact and shows
//     the server's sentence — a form that closes on a refusal loses what the
//     clerk typed;
//   * a second tap cannot post twice, and a success closes the dialog;
//   * it lays out at a 760 px window with 1.3x text, in the app's real fonts.

import 'dart:io';

import 'package:client/data/models/catalogue_item.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/services/catalogue_assembler.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/sales/widgets/sales_order_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

/// The app's own fonts: a 760 px / 1.3x layout claim made in Ahem measures text
/// nobody will ever see.
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

const _customers = [
  Customer(id: 3, name: 'Dela Cruz Construction', customerType: 'REGULAR'),
  Customer(id: 4, name: 'Reyes Trading', customerType: 'CONTRACTOR'),
];

/// Two selling units of one material plus a measured one, so the whole-unit rule
/// and the unit picker both have something real to answer.
List<CatalogueItem> _catalogue() => assembleCatalogue(
  products: [
    product(
      id: 1,
      name: 'Portland Cement',
      variants: [
        variant(
          id: 5,
          productId: 1,
          name: '40kg',
          baseUomCode: 'BAG',
          sellingUoms: [
            variantUom(
              id: 1,
              variantId: 5,
              price: 250,
              uomCode: 'BAG',
              uomName: 'Bag',
              isWhole: true,
            ),
            variantUom(
              id: 2,
              variantId: 5,
              price: 13,
              uomCode: 'KG',
              uomName: 'Kilogram',
            ),
          ],
        ),
      ],
    ),
  ],
  batches: [batch(id: 1, variantId: 5, qty: 100)],
);

void _sizeUp(WidgetTester tester, {Size size = const Size(1400, 1100)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  setUpAll(_loadAppFonts);

  late List<SalesOrderDraft> submitted;
  late SalesServiceException? refusal;

  setUp(() {
    submitted = [];
    refusal = null;
  });

  /// Opens the dialog with a recording submit callback. [hold] makes the submit
  /// hang, so a test can tap twice into a request that is still in flight.
  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(1400, 1100),
    double scale = 1.0,
    List<CatalogueItem>? catalogue,
    bool hold = false,
  }) async {
    _sizeUp(tester, size: size);
    await tester.pumpWidget(
      MaterialApp(
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
                builder: (_) => SalesOrderFormDialog(
                  customers: _customers,
                  catalogue: catalogue ?? _catalogue(),
                  onSubmit: (draft) async {
                    submitted.add(draft);
                    if (hold) {
                      await Future<void>.delayed(
                        const Duration(milliseconds: 200),
                      );
                    }
                    return refusal;
                  },
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  /// Fills the first line: the unit is already the catalogue's first one, so a
  /// test only sets the numbers it cares about.
  Future<void> fillLine(
    WidgetTester tester, {
    String qty = '2',
    String? price,
  }) async {
    await tester.enterText(find.byKey(const ValueKey('so-qty-0')), qty);
    if (price != null) {
      await tester.enterText(find.byKey(const ValueKey('so-price-0')), price);
    }
    await tester.pumpAndSettle();
  }

  Future<void> chooseCustomer(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(const ValueKey('so-customer')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('so-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('the form is the dialog family, with a customer and one line', (
    tester,
  ) async {
    await open(tester);

    expect(find.text('New sales order'), findsOneWidget);
    expect(find.byKey(const ValueKey('so-customer')), findsOneWidget);
    // The selling unit the catalogue prices, named as the reader sees it.
    expect(find.textContaining('Portland Cement 40kg'), findsWidgets);
    expect(find.byKey(const ValueKey('so-qty-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('so-price-0')), findsOneWidget);
    // Deliver is off until it is switched on.
    expect(find.byKey(const ValueKey('so-deliver-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('so-delivery-address')), findsNothing);
    // Create-only: there is no status control anywhere on the form.
    expect(find.textContaining('Status'), findsNothing);
  });

  testWidgets('submitting posts customer, line and notes and no status', (
    tester,
  ) async {
    await open(tester);
    await chooseCustomer(tester, 'Dela Cruz Construction');
    await fillLine(tester, qty: '2', price: '250');
    await tester.enterText(find.byKey(const ValueKey('so-notes')), 'After 3pm');
    await tester.pumpAndSettle();
    await submit(tester);

    expect(submitted, hasLength(1));
    final body = submitted.single.toJson();
    expect(body['customer'], 3);
    expect(body['notes'], 'After 3pm');
    expect(body['items'], [
      {'variant_uom': 1, 'qty': 2.0, 'unit_price': '250.00'},
    ]);
    expect(body.containsKey('status'), isFalse);
    expect(body.containsKey('delivery'), isFalse);
    // A success closes the form.
    expect(find.byType(SalesOrderFormDialog), findsNothing);
  });

  // Live QA 2026-11-12: every catalogue row is one product's unit, so a picker
  // listing only "PC (Piece)" nine times picks a product the clerk cannot see.
  testWidgets('the unit picker names the product behind every unit', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('so-unit-0')));
    await tester.pumpAndSettle();

    // The open menu is the last copy of each item (the button keeps one too).
    for (final label in [
      'Portland Cement 40kg · BAG',
      'Portland Cement 40kg · KG',
    ]) {
      expect(
        find.textContaining(label),
        findsWidgets,
        reason: 'a unit code alone does not say which product is ordered',
      );
    }
  });

  // Live QA 2026-11-12: switching a line to another product's unit moved the
  // price but left the old product's name on the line.
  testWidgets('a line is headed by the product of its chosen unit', (
    tester,
  ) async {
    await open(
      tester,
      catalogue: assembleCatalogue(
        products: [
          product(
            id: 2,
            name: 'Circuit Breaker',
            variants: [
              variant(
                id: 8,
                productId: 2,
                name: '20A',
                sellingUoms: [
                  variantUom(id: 8, variantId: 8, price: 315, uomCode: 'PC'),
                ],
              ),
            ],
          ),
          ..._catalogue().map((item) => item.product).toSet(),
        ],
        batches: const [],
      ),
    );
    expect(find.text('Circuit Breaker 20A'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('so-unit-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portland Cement 40kg · BAG (Bag)').last);
    await tester.pumpAndSettle();

    expect(find.text('Portland Cement 40kg'), findsOneWidget);
    expect(find.text('Circuit Breaker 20A'), findsNothing);
  });

  // Live QA 2026-11-12: an archived product was offered, and preselected as the
  // first line. The till never sells one, so neither does an order.
  testWidgets('archived products and variants are not offered', (tester) async {
    VariantUom bag(int id, int variantId) => variantUom(
      id: id,
      variantId: variantId,
      price: 10,
      uomCode: 'BAG',
      uomName: 'Bag',
      isWhole: true,
    );
    await open(
      tester,
      catalogue: assembleCatalogue(
        products: [
          product(
            id: 9,
            name: 'Archived Mix',
            isActive: false,
            variants: [
              variant(id: 9, productId: 9, sellingUoms: [bag(9, 9)]),
            ],
          ),
          product(
            id: 7,
            name: 'Old Sand',
            variants: [
              variant(
                id: 7,
                productId: 7,
                name: 'Retired',
                isActive: false,
                sellingUoms: [bag(7, 7)],
              ),
            ],
          ),
          ..._catalogue().map((item) => item.product).toSet(),
        ],
        batches: const [],
      ),
    );

    // The first line starts on a product that can still be sold.
    expect(find.textContaining('Portland Cement 40kg'), findsWidgets);
    expect(find.textContaining('Archived Mix'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('so-unit-0')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Archived Mix'), findsNothing);
    expect(find.textContaining('Old Sand'), findsNothing);
  });

  testWidgets('the price starts at the selling unit price the catalogue '
      'charges', (tester) async {
    await open(tester);

    final price = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('so-price-0')),
        matching: find.byType(TextField),
      ),
    );
    expect(price.controller!.text, '250.00');
    expect(find.textContaining('₱250.00'), findsWidgets);
  });

  testWidgets('a whole unit refuses a fractional count before any request', (
    tester,
  ) async {
    await open(tester);
    await chooseCustomer(tester, 'Dela Cruz Construction');
    await fillLine(tester, qty: '1.5');
    await submit(tester);

    expect(submitted, isEmpty, reason: 'the server would refuse this anyway');
    expect(
      find.textContaining('whole'),
      findsWidgets,
      reason: 'the form says which rule the number breaks',
    );
    expect(find.byType(SalesOrderFormDialog), findsOneWidget);
  });

  // Live QA: the whole-unit sentence was unreadable — Material draws a field's
  // error as ONE ellipsized line, and the quantity field is half a dialog wide.
  // "BAG is sold in whole numb…" tells the clerk nothing they can act on, so the
  // field has to be allowed the lines the sentence needs.
  testWidgets('the whole-unit refusal renders in full at 760 px and 1.3x text', (
    tester,
  ) async {
    await open(tester, size: const Size(760, 1000), scale: 1.3);
    await chooseCustomer(tester, 'Dela Cruz Construction');
    await fillLine(tester, qty: '1.5');
    await submit(tester);

    const sentence = 'BAG is sold in whole numbers. Enter a whole number.';
    final error = find.text(sentence);
    expect(error, findsOneWidget, reason: 'the refusal names the unit rule');

    // The proof that nothing was ellipsized: the paragraph laid every glyph out.
    final paragraph = tester.renderObject<RenderParagraph>(error);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'a clipped error cannot be read or acted on',
    );
    // And it is drawn inside the field's own width, not pushed off the dialog.
    final field = tester.getRect(find.byKey(const ValueKey('so-qty-0')));
    expect(tester.getRect(error).width, lessThanOrEqualTo(field.width));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a measured unit takes a fractional count', (tester) async {
    await open(tester);
    await chooseCustomer(tester, 'Dela Cruz Construction');
    await tester.tap(find.byKey(const ValueKey('so-unit-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Portland Cement 40kg · KG (Kilogram)').last);
    await tester.pumpAndSettle();
    await fillLine(tester, qty: '1.5');
    await tester.pumpAndSettle();
    await submit(tester);

    expect(submitted, hasLength(1));
    expect(submitted.single.toJson()['items'], [
      {'variant_uom': 2, 'qty': 1.5, 'unit_price': '13.00'},
    ]);
  });

  testWidgets('Deliver sends the whole slip, fee at 2 dp and a plain date', (
    tester,
  ) async {
    await open(tester);
    await chooseCustomer(tester, 'Reyes Trading');
    await fillLine(tester, qty: '3');

    await tester.tap(find.byKey(const ValueKey('so-deliver-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-address')),
      '12 Mabini St, Cebu',
    );
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-contact')),
      'Ana Reyes',
    );
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-phone')),
      '0917 555 1234',
    );
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-fee')),
      '150',
    );
    await tester.pumpAndSettle();
    await submit(tester);

    expect(submitted, hasLength(1));
    final delivery = submitted.single.toJson()['delivery'];
    expect(delivery, isA<Map<String, dynamic>>());
    expect(delivery['address'], '12 Mabini St, Cebu');
    expect(delivery['contact_name'], 'Ana Reyes');
    expect(delivery['contact_phone'], '0917 555 1234');
    expect(delivery['fee'], '150.00');
    // `YYYY-MM-DD`, no timestamp: the server parses a plain date.
    expect(delivery['scheduled_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
  });

  testWidgets('a deliver order with a missing address is refused here', (
    tester,
  ) async {
    await open(tester);
    await chooseCustomer(tester, 'Reyes Trading');
    await fillLine(tester, qty: '3');
    await tester.tap(find.byKey(const ValueKey('so-deliver-toggle')));
    await tester.pumpAndSettle();
    await submit(tester);

    expect(submitted, isEmpty);
    expect(find.textContaining('address'), findsWidgets);
  });

  testWidgets('a zero fee is allowed (the fee is optional)', (tester) async {
    await open(tester);
    await chooseCustomer(tester, 'Reyes Trading');
    await fillLine(tester, qty: '1');
    await tester.tap(find.byKey(const ValueKey('so-deliver-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-address')),
      '12 Mabini St, Cebu',
    );
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-contact')),
      'Ana Reyes',
    );
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-phone')),
      '0917 555 1234',
    );
    await tester.enterText(find.byKey(const ValueKey('so-delivery-fee')), '0');
    await tester.pumpAndSettle();
    await submit(tester);

    expect(submitted, hasLength(1));
    expect(submitted.single.toJson()['delivery']['fee'], '0.00');
  });

  testWidgets('a fee with three decimals is refused rather than rounded', (
    tester,
  ) async {
    await open(tester);
    await chooseCustomer(tester, 'Reyes Trading');
    await fillLine(tester, qty: '1');
    await tester.tap(find.byKey(const ValueKey('so-deliver-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-address')),
      '12 Mabini St, Cebu',
    );
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-contact')),
      'Ana Reyes',
    );
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-phone')),
      '0917 555 1234',
    );
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-fee')),
      '10.005',
    );
    await tester.pumpAndSettle();
    await submit(tester);

    expect(submitted, isEmpty);
    expect(find.textContaining('two decimals'), findsWidgets);
  });

  testWidgets('a server refusal keeps the form open with the input intact', (
    tester,
  ) async {
    refusal = const SalesServiceException(
      'Cement 40kg, BAG: a whole unit takes a whole number of units.',
    );
    await open(tester);
    await chooseCustomer(tester, 'Dela Cruz Construction');
    await fillLine(tester, qty: '2');
    await submit(tester);

    expect(submitted, hasLength(1));
    expect(find.byType(SalesOrderFormDialog), findsOneWidget);
    expect(find.text(refusal!.message), findsOneWidget);
    // The input the clerk typed is still there.
    final qty = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('so-qty-0')),
        matching: find.byType(TextField),
      ),
    );
    expect(qty.controller!.text, '2');
    expect(find.text('Dela Cruz Construction'), findsWidgets);
  });

  testWidgets('a second tap while the first is in flight posts once', (
    tester,
  ) async {
    await open(tester, hold: true);
    await chooseCustomer(tester, 'Dela Cruz Construction');
    await fillLine(tester, qty: '2');

    await tester.tap(find.byKey(const ValueKey('so-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('so-submit')));
    await tester.pumpAndSettle();

    expect(submitted, hasLength(1));
  });

  testWidgets('a customer is required', (tester) async {
    await open(tester);
    await fillLine(tester, qty: '2');
    await submit(tester);

    expect(submitted, isEmpty);
    expect(find.textContaining('customer'), findsWidgets);
  });

  testWidgets('lays out at 760 px with 1.3x text', (tester) async {
    await open(
      tester,
      size: const Size(760, 1000),
      scale: 1.3,
      catalogue: _catalogue(),
    );
    await tester.tap(find.byKey(const ValueKey('so-deliver-toggle')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('so-delivery-address')), findsOneWidget);
    expect(find.byKey(const ValueKey('so-submit')), findsOneWidget);
    final rect = tester.getRect(find.byType(SalesOrderFormDialog));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(760));
  });

  testWidgets('an empty catalogue says so and cannot be submitted', (
    tester,
  ) async {
    await open(tester, catalogue: const []);
    await chooseCustomer(tester, 'Dela Cruz Construction');
    await submit(tester);

    expect(submitted, isEmpty);
    expect(find.textContaining('catalogue'), findsWidgets);
  });

  testWidgets('a price and a fee error render in full at 760 px and 1.3x', (
    tester,
  ) async {
    // Item 15: both money fields sit in a half-width column at 760 px, so their
    // refusal used to ellipsize to one line - a clipped error cannot be fixed.
    await open(tester, size: const Size(760, 1000), scale: 1.3);
    await chooseCustomer(tester, 'Dela Cruz Construction');
    await fillLine(tester, price: '-1');
    await tester.tap(find.byKey(const ValueKey('so-deliver-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('so-delivery-fee')),
      '10.005',
    );
    await tester.pumpAndSettle();
    await submit(tester);

    for (final sentence in [
      'Enter an amount, 0 or more.',
      'At most two decimals.',
    ]) {
      final error = find.text(sentence);
      expect(error, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(error).didExceedMaxLines,
        isFalse,
        reason: '"$sentence" must be readable in full',
      );
    }
  });
}
