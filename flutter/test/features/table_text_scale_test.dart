// Z2 fix A (ui-refresh): at 1.3x text the tables still show whole values.
//
// The QA sweep ran the browser at 1100 x 900 with a 1.3x root font and found
// four values cut to an ellipsis on columns that had room for one more word:
//
//   D-01 /inventory/stock-movements  "When" reads "Nov 2, 2026, 10..." (time lost)
//   D-03 /pos/shifts                 "Not counted yet" reads "Not count..."
//   D-04 /inventory/products         header "Variants" reads "Varia..."
//
//   D-02 /inventory/stock             Category "Plumbing" reads "Plumbi..."
//
// The fix is not a wider window: the same columns show these values whole at
// 1.0x, so the text has to be allowed a second line before it is cut.
//
// The metric is the one QA saw: the paragraph is asked to lay its text out
// without dropping any of it. Text is measured in the app's own faces (Open
// Sans, Cinzel) exactly as the browser renders it. The test font every other
// widget test falls back to is one em per character, roughly twice as wide as
// Open Sans, so measuring with it would demand a layout twice as wide as the
// real screen needs, and would let a real regression hide behind that slack.

import 'dart:io';

import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_stock_page.dart';
import 'package:client/features/inventory/views/inventory_stock_movements_page.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_shift_page.dart';
import 'package:client/features/products/views/products_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/phase4_fakes.dart';

/// The sweep's window.
const _laptop = Size(1100, 900);

/// The sweep's root font size.
const _sweepScale = TextScaler.linear(1.3);

/// A browser at 1.3x root font, over [home].
Widget _atSweepScale(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AppTheme.lightTheme,
  home: home,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: _sweepScale),
    child: child!,
  ),
);

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

/// The paragraph behind the one Text that says [text] - what the pixel on
/// screen is drawn from, and the only place that knows whether the text was
/// cut off.
RenderParagraph _paragraph(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsOneWidget, reason: 'expected one "$text" on screen');
  return tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
}

/// Every paragraph that says [text] - a header and a button label share one
/// word, and a two row table repeats its values - must have laid its text out
/// without cutting it.
void _expectWhole(WidgetTester tester, String text) {
  final finder = find.text(text);
  expect(finder, findsWidgets, reason: 'expected "$text" on screen');
  for (final element in finder.evaluate()) {
    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byElementPredicate((e) => e == element),
        matching: find.byType(RichText),
      ),
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: '"$text" is cut off at 1.3x',
    );
  }
}

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('D-01: the "When" cell shows the whole date and time at 1.3x', (
    tester,
  ) async {
    tester.view.physicalSize = _laptop;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Inside the page's default "this month" period.
    final stamp = DateTime(2026, 10, 15, 7);
    final store = InventoryViewmodel(
      products: FakeProductsRepository(
        products: [
          product(
            id: 1,
            name: 'Portland Cement 40 kg bag, type 1P, pallet of 40 bags',
            categoryName: 'Plumbing',
            variants: [
              variant(
                id: 1,
                productId: 1,
                name: '1/2 inch',
                threshold: 30,
                baseUomCode: 'PC',
              ),
            ],
          ),
        ],
      ),
      inventory: FakeInventoryRepository(
        adjustments: [
          StockAdjustment(
            id: 1,
            variantId: 1,
            userId: 7,
            adjustmentType: StockAdjustmentType.damage,
            quantityAdjusted: -2,
            remarks: 'Cracked casing.',
            timestamp: stamp,
          ),
        ],
      ),
      catalogue: FakeCatalogueRepository(),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>(
        create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        child: ChangeNotifierProvider<InventoryViewmodel>.value(
          value: store,
          child: _atSweepScale(const InventoryStockMovementsPage()),
        ),
      ),
    );
    await store.load();
    await tester.pumpAndSettle();

    final when = _paragraph(tester, formatDateTime(stamp));
    expect(
      when.didExceedMaxLines,
      isFalse,
      reason: 'the time must not be cut off: the cell needs a second line',
    );
    // A long product name still ends in an ellipsis: the second line is for a
    // value that is one word too long, not a licence to grow every row.
    expect(
      _paragraph(
        tester,
        'Portland Cement 40 kg bag, type 1P, pallet of 40 bags',
      ).didExceedMaxLines,
      isTrue,
    );
  });

  testWidgets('D-02: the stock book shows the whole category at 1.3x', (
    tester,
  ) async {
    tester.view.physicalSize = _laptop;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(const {});
    final store = seededInventory();
    await store.loadLocationHints();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>(
            create: (_) => AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
        ],
        child: _atSweepScale(const InventoryStockPage()),
      ),
    );
    await tester.pumpAndSettle();

    // The category is one word with no break in it, so a second line would only
    // split it ("Plumbi"/"ng"): the column itself has to be wide enough.
    expect(
      _paragraph(tester, 'Plumbing').didExceedMaxLines,
      isFalse,
      reason: 'a one word category must not read "Plumbi..."',
    );

    // The room came from the other columns' shares, so they must still fit: the
    // product name beside it, every header, the status badge and the action.
    for (final text in [
      'Product',
      'Category',
      'On hand',
      'Reorder level',
      'Status',
      'Adjust',
      'Portland Cement',
      'Cement',
      'In Stock',
    ]) {
      _expectWhole(tester, text);
    }
  });

  testWidgets('D-03: an uncounted drawer says the whole sentence at 1.3x', (
    tester,
  ) async {
    tester.view.physicalSize = _laptop;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final service = _StubShifts()
      ..current = _shift()
      ..history = [_shift()];

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: AuthViewmodel(AuthRepository(AuthService())),
        child: _atSweepScale(
          PosShiftPage(viewmodel: ShiftViewmodel(service: service)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The open row has no count and no reading: two "Not counted yet" cells.
    final cells = find.text('Not counted yet');
    expect(cells, findsNWidgets(2));
    for (final cell in cells.evaluate()) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byElementPredicate((e) => e == cell),
          matching: find.byType(RichText),
        ),
      );
      expect(
        paragraph.didExceedMaxLines,
        isFalse,
        reason: '"Not counted yet" must read as a sentence, not "Not count..."',
      );
    }
  });

  testWidgets('D-04: the "Variants" header is not cut to "Varia..." at 1.3x', (
    tester,
  ) async {
    tester.view.physicalSize = _laptop;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = InventoryViewmodel(
      products: FakeProductsRepository(
        products: [
          product(
            id: 1,
            name: 'Portland Cement 40 kg bag',
            categoryName: 'Cement',
            brandName: 'Holcim',
            variants: [
              variant(
                id: 11,
                productId: 1,
                name: '40 kg bag',
                sellingUoms: [
                  variantUom(
                    id: 111,
                    variantId: 11,
                    price: 315,
                    barcode: 'QB000011-2',
                    uomCode: 'BAG',
                  ),
                ],
              ),
            ],
          ),
        ],
        batches: [batch(id: 1, variantId: 11, qty: 120)],
      ),
      inventory: FakeInventoryRepository(),
      catalogue: FakeCatalogueRepository(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
        ],
        child: _atSweepScale(const ProductsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      _paragraph(tester, 'Variants').didExceedMaxLines,
      isFalse,
      reason: 'a header one word long must not be cut to "Varia..."',
    );
    // The count under it still fits: the width came from the header, not from
    // squeezing the cell.
    final count = tester.renderObject<RenderParagraph>(
      find
          .descendant(
            of: find.byKey(const ValueKey('DataPanel.table')),
            matching: find.text('1'),
          )
          .first,
    );
    expect(count.didExceedMaxLines, isFalse);
  });
}

class _StubShifts extends ShiftService {
  Shift? current;
  List<Shift> history = const [];

  @override
  Future<Shift?> fetchCurrent() async => current;

  @override
  Future<List<Shift>> fetchAll() async => history;

  @override
  Future<Shift> openShift(double openingFloat) async => current!;
}

/// An open drawer nobody has counted, and no Z-reading on it yet: the row says
/// so in words on two money columns.
Shift _shift() => Shift(
  id: 1,
  cashierName: 'Ana Cruz',
  status: Shift.openStatus,
  openingFloat: 5000,
  closingCount: null,
  openedAt: DateTime(2026, 10, 15, 8),
  closedAt: null,
  notes: '',
  zReading: null,
);
