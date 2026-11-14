// Phase 9 F3 (decision 21 §3): the transfers screen and its record dialog.
//
// Pinned here, in the shells the routes mount:
//   * a slip row says what moved, between which shelves, when and by whom, and
//     opens the readable slip with each line's units and stock;
//   * the dialog offers every shelf as a SOURCE but only an ACTIVE one as a
//     DESTINATION (Design 11), refuses the same shelf twice, and refuses a
//     fraction of a whole selling unit before spending a request;
//   * a refusal is the server's own sentence, shown INLINE, with every typed
//     value kept;
//   * one click moves stock once — a second press while the first is on the
//     wire posts nothing;
//   * at 760 px with 1.3x text the page and the dialog render whole.

import 'dart:async';
import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/stock_transfer.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/repositories/stock_transfer_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/stock_transfer_service.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/transfers/viewmodels/transfers_viewmodel.dart';
import 'package:client/features/transfers/views/transfers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

const _bagLabel = 'Portland cement · 40kg · BAG';

StockTransfer _transfer({
  int id = 1,
  String number = 'TR-20261113-0001',
  String remarks = 'Shelf refill',
  List<StockTransferLine>? lines,
}) => StockTransfer(
  id: id,
  number: number,
  fromLocationId: 1,
  fromLocationName: 'Store',
  toLocationId: 2,
  toLocationName: 'Bodega',
  userId: 7,
  userName: 'Ana Lopez',
  remarks: remarks,
  createdAt: DateTime(2026, 11, 13, 9, 15),
  lines:
      lines ??
      const [
        StockTransferLine(
          id: 11,
          variantUomId: 4,
          variantId: 8,
          variantName: '40kg',
          productName: 'Portland cement',
          unit: 'BAG',
          qty: 2,
          baseQty: 80,
          moves: [
            StockTransferMove(
              id: 21,
              sourceBatchId: 5,
              destBatchId: 9,
              qty: 40,
            ),
            StockTransferMove(
              id: 22,
              sourceBatchId: 6,
              destBatchId: 10,
              qty: 40,
            ),
          ],
        ),
      ],
);

Product _cement() => const Product(
  id: 6,
  categoryId: 1,
  categoryName: 'Cement',
  brandId: 1,
  brandName: 'Holcim',
  baseName: 'Portland cement',
  description: '',
  imageUrl: '',
  isActive: true,
  storedAtId: 1,
  storedAtName: 'Store',
  variants: [
    ProductVariant(
      id: 8,
      productId: 6,
      baseUomId: 2,
      minStockThreshold: 5,
      maxStockLevel: 0,
      variantName: '40kg',
      baseUomCode: 'PC',
      isActive: true,
      sellingUoms: [
        VariantUom(
          id: 4,
          variantId: 8,
          uomId: 3,
          uomCode: 'BAG',
          uomName: 'Bag',
          barcodeQr: '',
          conversionFactor: 40,
          defaultSellingPrice: 300,
          uomIsWhole: true,
        ),
      ],
    ),
  ],
);

class _FakeProductsRepository extends ProductsRepository {
  _FakeProductsRepository(this.products) : super(ProductsService());

  final List<Product> products;

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      ProductsSnapshot(products: products, batches: const []);
}

class _FakeTransfers extends StockTransferRepository {
  _FakeTransfers({List<StockTransfer> transfers = const []})
    : _transfers = [...transfers];

  List<StockTransfer> _transfers;
  final List<StockTransferRequest> posted = [];

  /// Held to keep a write on the wire, so a second click can be attempted.
  Completer<void>? gate;
  String? writeError;

  @override
  Future<List<StockTransfer>> fetchAll() async => [..._transfers];

  @override
  Future<StockTransfer> create(StockTransferRequest request) async {
    final held = gate;
    if (held != null) await held.future;
    posted.add(request);
    final error = writeError;
    if (error != null) throw StockTransferServiceException(error);
    final recorded = _transfer(
      id: 100 + posted.length,
      number: 'TR-20261113-0100',
      remarks: request.remarks,
    );
    _transfers = [recorded, ..._transfers];
    return recorded;
  }
}

TransfersViewmodel _state({
  _FakeTransfers? transfers,
  List<StorageLocation>? shelves,
}) => TransfersViewmodel(
  repository: transfers ?? _FakeTransfers(),
  locations: FakeStorageLocationRepository(
    locations:
        shelves ??
        const [
          StorageLocation(id: 1, name: 'Store'),
          StorageLocation(id: 2, name: 'Bodega'),
          StorageLocation(id: 3, name: 'Yard', isActive: false),
        ],
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

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  Size size = const Size(1400, 1000),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewmodel>(
          create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the dropdown behind [key] and taps [label].
Future<void> _choose(WidgetTester tester, String key, String label) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Fills the dialog's first line and both shelves, the happy path.
Future<void> _fill(
  WidgetTester tester, {
  String from = 'Store',
  String to = 'Bodega',
  String qty = '2',
}) async {
  await _choose(tester, 'transfer-from', from);
  await _choose(tester, 'transfer-to', to);
  await _choose(tester, 'transfer-line-uom-0', _bagLabel);
  await tester.enterText(
    find.byKey(const ValueKey('transfer-line-qty-0')),
    qty,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(_loadAppFonts);

  testWidgets('a slip row says what moved, between which shelves and by whom', (
    tester,
  ) async {
    await _pump(
      tester,
      InventoryTransfersPage(
        viewmodel: _state(transfers: _FakeTransfers(transfers: [_transfer()])),
        products: _FakeProductsRepository([_cement()]),
      ),
    );

    expect(find.text('TR-20261113-0001'), findsOneWidget);
    expect(find.text('Store → Bodega'), findsOneWidget);
    expect(find.text('Shelf refill'), findsOneWidget);
    expect(find.text('Ana Lopez'), findsOneWidget);
    expect(find.textContaining('80'), findsWidgets);
  });

  testWidgets('the slip opens whole: units typed, stock moved, lots drawn', (
    tester,
  ) async {
    await _pump(
      tester,
      SalesTransfersPage(
        viewmodel: _state(transfers: _FakeTransfers(transfers: [_transfer()])),
        products: _FakeProductsRepository([_cement()]),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('transfer-slip-1')));
    await tester.pumpAndSettle();

    expect(find.text('Portland cement · 40kg'), findsOneWidget);
    expect(
      find.textContaining('2 BAG'),
      findsOneWidget,
      reason: 'the slip speaks the unit the clerk counted',
    );
    expect(
      find.textContaining('drawn from 2 lots'),
      findsOneWidget,
      reason: 'two delivery lots paid for one line, and the slip says so',
    );
    expect(find.textContaining('Recorded by Ana Lopez'), findsOneWidget);
  });

  testWidgets('recording a transfer posts the selling unit once', (
    tester,
  ) async {
    final transfers = _FakeTransfers(transfers: [_transfer()]);
    await _pump(
      tester,
      InventoryTransfersPage(
        viewmodel: _state(transfers: transfers),
        products: _FakeProductsRepository([_cement()]),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('transfers-record')));
    await tester.pumpAndSettle();
    await _fill(tester);
    await tester.tap(find.byKey(const ValueKey('transfer-submit')));
    await tester.pumpAndSettle();

    expect(transfers.posted, hasLength(1));
    expect(transfers.posted.single.fromLocationId, 1);
    expect(transfers.posted.single.toLocationId, 2);
    expect(transfers.posted.single.lines.single.variantUomId, 4);
    expect(transfers.posted.single.lines.single.qty, 2);
    expect(
      find.textContaining('TR-20261113-0100'),
      findsWidgets,
      reason: 'the numbered slip is the answer, not a silent close',
    );
  });

  testWidgets('a deactivated shelf is never offered as a destination', (
    tester,
  ) async {
    await _pump(
      tester,
      AdminTransfersPage(
        viewmodel: _state(),
        products: _FakeProductsRepository([_cement()]),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('transfers-record')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-to')));
    await tester.pumpAndSettle();

    expect(find.text('Bodega'), findsWidgets);
    expect(
      find.text('Yard'),
      findsNothing,
      reason:
          'the server refuses an inactive destination; the picker must not '
          'offer it',
    );

    // The same deactivated shelf stays available as a SOURCE: stock already on
    // a closed shelf is emptied by transferring it OUT (Design 11).
    await tester.tap(find.text('Bodega').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('transfer-from')));
    await tester.pumpAndSettle();
    expect(find.text('Yard'), findsWidgets);
  });

  testWidgets('the same shelf twice is refused before any request', (
    tester,
  ) async {
    final transfers = _FakeTransfers();
    await _pump(
      tester,
      InventoryTransfersPage(
        viewmodel: _state(transfers: transfers),
        products: _FakeProductsRepository([_cement()]),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('transfers-record')));
    await tester.pumpAndSettle();
    await _fill(tester, to: 'Store', qty: '2');
    await tester.tap(find.byKey(const ValueKey('transfer-submit')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('two different shelves'),
      findsOneWidget,
      reason: 'moving store-to-store is not a move',
    );
    expect(transfers.posted, isEmpty);
  });

  testWidgets('half a bag is refused inline, with nothing posted', (
    tester,
  ) async {
    final transfers = _FakeTransfers();
    await _pump(
      tester,
      InventoryTransfersPage(
        viewmodel: _state(transfers: transfers),
        products: _FakeProductsRepository([_cement()]),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('transfers-record')));
    await tester.pumpAndSettle();
    await _fill(tester, qty: '2.5');
    await tester.tap(find.byKey(const ValueKey('transfer-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Counted in whole BAG.'), findsOneWidget);
    expect(transfers.posted, isEmpty, reason: 'the server would refuse it too');
  });

  testWidgets('a refusal is the server sentence, inline, values kept', (
    tester,
  ) async {
    final transfers = _FakeTransfers()
      ..writeError =
          'Not enough Portland cement at Store: 3.00 BAG short of the 5 BAG '
          'this line moves.';
    await _pump(
      tester,
      InventoryTransfersPage(
        viewmodel: _state(transfers: transfers),
        products: _FakeProductsRepository([_cement()]),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('transfers-record')));
    await tester.pumpAndSettle();
    await _fill(tester, qty: '5');
    await tester.tap(find.byKey(const ValueKey('transfer-submit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('transfer-refusal')),
      findsOneWidget,
      reason: 'the dialog says why, over the values the clerk typed',
    );
    expect(
      find.textContaining('3.00 BAG short'),
      findsWidgets,
      reason:
          'the sentence is shown inline over the form, and stays on the page '
          'banner behind it so it is still readable once the dialog closes',
    );
    expect(
      find.byKey(const ValueKey('transfer-line-qty-0')),
      findsOneWidget,
      reason: 'a refusal must not close the form and lose the slip',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('transfer-line-qty-0')),
          )
          .controller!
          .text,
      '5',
    );
  });

  testWidgets('a second click while the first is on the wire posts nothing', (
    tester,
  ) async {
    final transfers = _FakeTransfers()..gate = Completer<void>();
    await _pump(
      tester,
      InventoryTransfersPage(
        viewmodel: _state(transfers: transfers),
        products: _FakeProductsRepository([_cement()]),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('transfers-record')));
    await tester.pumpAndSettle();
    await _fill(tester, qty: '3');

    await tester.tap(find.byKey(const ValueKey('transfer-submit')));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('transfer-submit')),
      warnIfMissed: false,
    );
    await tester.pump();

    transfers.gate!.complete();
    await tester.pumpAndSettle();

    expect(
      transfers.posted,
      hasLength(1),
      reason: 'two slips would move the same stock twice',
    );
  });

  testWidgets('760 px at 1.3x text, the page and the dialog render whole', (
    tester,
  ) async {
    await _pump(
      tester,
      InventoryTransfersPage(
        viewmodel: _state(transfers: _FakeTransfers(transfers: [_transfer()])),
        products: _FakeProductsRepository([_cement()]),
      ),
      size: const Size(760, 900),
      scale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Transfers'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('transfers-record')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await _fill(tester, qty: '2');
    await tester.ensureVisible(find.byKey(const ValueKey('transfer-submit')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
