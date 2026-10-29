// Phase 6 Task 5 (decisions 13 + 17): what a scan does at the till.
//
// Before this, `_handleScan` only ever consulted the loaded catalogue and then
// opened the quantity dialog — so a box and a piece of one variant behaved the
// same (F3/F4), a unit created after the till opened was "not found" forever, and
// a measured unit was one Enter away from selling "1 m" by accident.
//
// Every outcome below is asserted from the CART, not from pixels: the cart is what
// the customer is charged for.

import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_scan_result.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

const _boxCode = 'QB000013-0';
const _pcCode = 'QB000012-3';
const _metreCode = 'QB000020-7';
const _shortCode = 'QB000005-2';
const _unknownCode = 'QB000099-1';

/// Copper Wire, sold by the piece (id 120) and by the box (id 130).
Product wireProduct() => product(
  id: 12,
  name: 'Copper Wire',
  variants: [
    variant(
      id: 12,
      productId: 12,
      name: 'THHN 3.5mm',
      baseUomCode: 'PC',
      sellingUoms: const [
        VariantUom(
          id: 120,
          variantId: 12,
          uomId: 1,
          uomCode: 'PC',
          uomName: 'Piece',
          barcodeQr: _pcCode,
          conversionFactor: 1,
          defaultSellingPrice: 20,
        ),
        VariantUom(
          id: 130,
          variantId: 12,
          uomId: 2,
          uomCode: 'BOX',
          uomName: 'Box of 100',
          barcodeQr: _boxCode,
          conversionFactor: 100,
          defaultSellingPrice: 1900,
        ),
      ],
    ),
  ],
);

/// THHN Wire, sold by the piece (id 200, the FIRST option) and by the metre
/// (id 201, MEASURED — the unit a scan must preselect).
Product measuredProduct() => product(
  id: 20,
  name: 'THHN Wire',
  variants: [
    variant(
      id: 20,
      productId: 20,
      name: 'Stranded',
      baseUomCode: 'PC',
      sellingUoms: const [
        VariantUom(
          id: 200,
          variantId: 20,
          uomId: 1,
          uomCode: 'PC',
          uomName: 'Piece',
          barcodeQr: 'QB000020-8',
          conversionFactor: 1,
          defaultSellingPrice: 90,
        ),
        VariantUom(
          id: 201,
          variantId: 20,
          uomId: 2,
          uomCode: 'M',
          uomName: 'Metre',
          barcodeQr: _metreCode,
          conversionFactor: 1,
          defaultSellingPrice: 12,
        ),
      ],
    ),
  ],
);

/// PVC Pipe: a whole unit (PC) with less than one whole unit in stock, which is
/// the shape that makes `addLine` refuse a scan.
Product shortProduct() => product(
  id: 5,
  name: 'PVC Pipe',
  variants: [
    variant(
      id: 5,
      productId: 5,
      name: '1/2 inch',
      baseUomCode: 'PC',
      sellingUoms: const [
        VariantUom(
          id: 50,
          variantId: 5,
          uomId: 1,
          uomCode: 'PC',
          uomName: 'Piece',
          barcodeQr: _shortCode,
          conversionFactor: 1,
          defaultSellingPrice: 95,
        ),
      ],
    ),
  ],
);

List<InventoryBatch> allBatches() => [
  batch(id: 1, variantId: 12, qty: 500, cost: 10),
  batch(id: 2, variantId: 20, qty: 40, cost: 5),
  // 0.5 of a whole unit: in the catalogue (stock > 0) but not addable as 1.
  batch(id: 3, variantId: 5, qty: 0.5, cost: 60),
];

/// Answers `loadCatalogue()` with a snapshot the test can swap, and
/// `lookupByBarcode()` with rows (or a failure) the test writes down.
class _ScanProductsRepository extends ProductsRepository {
  _ScanProductsRepository({
    List<Product> products = const [],
    List<InventoryBatch> batches = const [],
  }) : rows = const [], snapshot = ProductsSnapshot(products: products, batches: batches),
       super(ProductsService());

  ProductsSnapshot snapshot;
  List<VariantUom> rows;
  int lookups = 0;
  int loads = 0;
  ProductsServiceException? failure;

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    loads++;
    return snapshot;
  }

  @override
  Future<List<VariantUom>> lookupByBarcode(String code) async {
    lookups++;
    final boom = failure;
    if (boom != null) throw boom;
    return rows;
  }
}

class _OpenShift extends ShiftService {
  @override
  Future<Shift?> fetchCurrent() async => Shift(
    id: 1,
    cashierName: 'Ana Cruz',
    status: Shift.openStatus,
    openingFloat: 5000,
    closingCount: null,
    openedAt: DateTime(2026, 10, 21, 8),
    closedAt: null,
    notes: '',
    zReading: null,
  );
}

/// Tracking gives the box its 100-piece factor, which is what makes "the box
/// unit was added" distinguishable from "one piece was added".
ProductTrackingViewmodel trackedProducts() {
  final tracking = ProductTrackingViewmodel();
  tracking.save(
    const ProductTrackingConfiguration(
      productName: 'Copper Wire',
      method: ProductTrackingMethod.quantity,
      baseUnit: 'pc',
      stockForm: ProductStockForm.packaged,
      allowFractional: false,
      allowPartialPackage: false,
      packageType: 'box',
      packageSize: 100,
      initialPackages: 5,
      totalBaseQuantity: 500,
      reorderLevel: 10,
      storageLocation: 'A1',
      costPrice: 10,
      sellingPrice: 20,
      packageSellingPrice: 1900,
      standardLength: 0,
      allowedSaleUnits: ['pc', 'box'],
      physicalPieces: [],
    ),
  );
  return tracking;
}

InventoryViewmodel _seededCatalogue(_ScanProductsRepository repository) =>
    InventoryViewmodel.seeded(
      catalogue: repository,
      // A `load()` runs on open and on a scan fallback, so the OTHER sources must
      // be fakes too: a real service would reach a Dio no unit test initialised.
      inventory: FakeInventoryRepository(),
      catalogueLists: FakeCatalogueRepository(),
      products: repository.snapshot.products,
      batches: repository.snapshot.batches,
    );

/// The till's scan field — the one field the USB wedge types into.
Finder scanField() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.hintText == 'Search or scan a Queen Builders barcode',
);

Future<void> pumpTill(
  WidgetTester tester, {
  required InventoryViewmodel inventory,
  required PosTransactionViewmodel cart,
  required ProductTrackingViewmodel tracking,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: AuthViewmodel(AuthRepository(AuthService())),
        ),
        ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
        ChangeNotifierProvider<ProductTrackingViewmodel>.value(value: tracking),
      ],
      child: MaterialApp(
        home: PosTransactionPage(
          viewmodel: cart,
          shiftViewmodel: ShiftViewmodel(service: _OpenShift()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Types a code into the scan field and presses Enter, the way a keyboard-wedge
/// scanner does.
Future<void> scan(WidgetTester tester, String code) async {
  await tester.enterText(scanField(), code);
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pumpAndSettle();
}

void main() {
  group('resolveScan', () {
    late _ScanProductsRepository repository;
    late InventoryViewmodel inventory;
    late PosTransactionViewmodel cart;

    setUp(() {
      repository = _ScanProductsRepository(
        products: [wireProduct()],
        batches: allBatches(),
      );
      inventory = _seededCatalogue(repository);
      cart = PosTransactionViewmodel(
        inventory,
        trackedProducts(),
        products: repository,
      );
    });

    test('a catalogue hit is answered without asking the server', () async {
      final result = await cart.resolveScan(' qb000013-0 ');

      expect(result, isA<ScanHit>());
      expect((result as ScanHit).item.variantUomId, 130);
      expect(
        repository.lookups,
        0,
        reason: 'the loaded catalogue is the fast path (decision 13)',
      );
    });

    test('an empty server answer is "no product has that code"', () async {
      final result = await cart.resolveScan(_unknownCode);

      expect(result, isA<ScanNotFound>());
      expect((result as ScanNotFound).code, _unknownCode);
      expect(repository.lookups, 1);
    });

    test('a server row whose variant is archived names the product', () async {
      repository.rows = [
        const VariantUom(
          id: 230,
          variantId: 23,
          uomId: 1,
          uomCode: 'PC',
          uomName: 'Piece',
          barcodeQr: _unknownCode,
          conversionFactor: 1,
          defaultSellingPrice: 10,
          productName: 'Old Cable',
          variantName: 'Discontinued',
          variantIsActive: false,
        ),
      ];

      final result = await cart.resolveScan(_unknownCode);

      expect(result, isA<ScanArchived>());
      expect((result as ScanArchived).productName, 'Old Cable');
      expect(result.code, _unknownCode);
      expect(
        repository.loads,
        0,
        reason: 'an archived row cannot become sellable by reloading',
      );
    });

    test('a server row that is active reloads the catalogue ONCE, then hits',
        () async {
      // The unit was created after the till loaded: the server knows it, the
      // catalogue does not. One reload, and the scan lands.
      final fresh = VariantUom(
        id: 230,
        variantId: 23,
        uomId: 1,
        uomCode: 'PC',
        uomName: 'Piece',
        barcodeQr: _unknownCode,
        conversionFactor: 1,
        defaultSellingPrice: 10,
        productName: 'Fresh Cable',
        variantName: 'New',
      );
      repository.rows = [fresh];
      repository.snapshot = ProductsSnapshot(
        products: [
          wireProduct(),
          product(
            id: 23,
            name: 'Fresh Cable',
            variants: [
              variant(
                id: 23,
                productId: 23,
                name: 'New',
                sellingUoms: [fresh],
              ),
            ],
          ),
        ],
        // Stock matters: the till catalogue offers nothing it cannot sell.
        batches: [...allBatches(), batch(id: 4, variantId: 23, qty: 12)],
      );

      final result = await cart.resolveScan(_unknownCode);

      expect(result, isA<ScanHit>());
      expect((result as ScanHit).item.variantUomId, 230);
      expect(repository.lookups, 1, reason: 'one fallback per scan, no retry');
      expect(repository.loads, 1, reason: 'one reload, not a loop');
    });

    test('a failed lookup is an error, never "not found"', () async {
      repository.failure = const ProductsServiceException(
        'Cannot connect to the BuildPro server.',
      );

      final result = await cart.resolveScan(_unknownCode);

      expect(result, isA<ScanError>());
      expect(
        (result as ScanError).message,
        'Cannot connect to the BuildPro server.',
      );
    });
  });

  group('the till scan flow', () {
    late _ScanProductsRepository repository;
    late InventoryViewmodel inventory;
    late ProductTrackingViewmodel tracking;
    late PosTransactionViewmodel cart;

    setUp(() {
      repository = _ScanProductsRepository(
        products: [wireProduct(), measuredProduct(), shortProduct()],
        batches: allBatches(),
      );
      inventory = _seededCatalogue(repository);
      tracking = trackedProducts();
      cart = PosTransactionViewmodel(
        inventory,
        tracking,
        products: repository,
      );
    });

    testWidgets('scanning a box code twice merges into one line of 2 boxes', (
      tester,
    ) async {
      await pumpTill(
        tester,
        inventory: inventory,
        cart: cart,
        tracking: tracking,
      );

      await scan(tester, _boxCode);
      await scan(tester, _boxCode);

      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.quantity, 2);
      expect(cart.lines.single.unit, 'BOX');
    });

    testWidgets('scanning a measured unit opens the dialog on THAT unit', (
      tester,
    ) async {
      await pumpTill(
        tester,
        inventory: inventory,
        cart: cart,
        tracking: tracking,
      );

      await scan(tester, _metreCode);

      expect(
        find.byType(AlertDialog),
        findsOneWidget,
        reason: 'a measured unit must be confirmed, never added silently',
      );
      await tester.tap(find.text('Add to cart'));
      await tester.pumpAndSettle();

      expect(cart.lines, hasLength(1));
      expect(
        cart.lines.single.unit,
        'M',
        reason: 'the scanned unit must be preselected (Barcode baseline F4)',
      );
    });

    testWidgets('a whole unit that cannot be added says why and changes nothing',
        (tester) async {
      await pumpTill(
        tester,
        inventory: inventory,
        cart: cart,
        tracking: tracking,
      );

      await scan(tester, _shortCode);

      expect(cart.lines, isEmpty);
      expect(find.text('Only 0.50 PC available.'), findsOneWidget);
    });

    testWidgets('a code the till had not loaded is found through the server', (
      tester,
    ) async {
      await pumpTill(
        tester,
        inventory: inventory,
        cart: cart,
        tracking: tracking,
      );
      final loadsAtOpen = repository.loads;

      final fresh = VariantUom(
        id: 330,
        variantId: 33,
        uomId: 1,
        uomCode: 'PC',
        uomName: 'Piece',
        barcodeQr: _unknownCode,
        conversionFactor: 1,
        defaultSellingPrice: 10,
        productName: 'Late Cable',
        variantName: 'New',
      );
      repository.rows = [fresh];
      repository.snapshot = ProductsSnapshot(
        products: [
          wireProduct(),
          measuredProduct(),
          shortProduct(),
          product(
            id: 33,
            name: 'Late Cable',
            variants: [
              variant(
                id: 33,
                productId: 33,
                name: 'New',
                sellingUoms: [fresh],
              ),
            ],
          ),
        ],
        batches: [...allBatches(), batch(id: 4, variantId: 33, qty: 12)],
      );

      await scan(tester, _unknownCode);

      expect(repository.lookups, 1);
      expect(repository.loads, loadsAtOpen + 1);
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.unit, 'PC');
    });

    testWidgets('an unknown code says no product has it', (tester) async {
      await pumpTill(
        tester,
        inventory: inventory,
        cart: cart,
        tracking: tracking,
      );

      await scan(tester, _unknownCode);

      expect(cart.lines, isEmpty);
      expect(find.text('No product has code `$_unknownCode`'), findsOneWidget);
    });

    testWidgets('a code on an archived product says so, naming the product', (
      tester,
    ) async {
      await pumpTill(
        tester,
        inventory: inventory,
        cart: cart,
        tracking: tracking,
      );
      repository.rows = [
        const VariantUom(
          id: 430,
          variantId: 43,
          uomId: 1,
          uomCode: 'PC',
          uomName: 'Piece',
          barcodeQr: _unknownCode,
          conversionFactor: 1,
          defaultSellingPrice: 10,
          productName: 'Old Cable',
          variantIsActive: false,
        ),
      ];

      await scan(tester, _unknownCode);

      expect(cart.lines, isEmpty);
      expect(
        find.text('`$_unknownCode` belongs to Old Cable, which is archived'),
        findsOneWidget,
      );
    });

    testWidgets('a failed lookup reports the error and does not crash', (
      tester,
    ) async {
      await pumpTill(
        tester,
        inventory: inventory,
        cart: cart,
        tracking: tracking,
      );
      repository.failure = const ProductsServiceException(
        'Cannot connect to the BuildPro server.',
      );

      await scan(tester, _unknownCode);

      expect(tester.takeException(), isNull);
      expect(cart.lines, isEmpty);
      expect(
        find.text('Cannot connect to the BuildPro server.'),
        findsOneWidget,
      );
    });

    testWidgets('browsing (not scanning) still preselects the first unit', (
      tester,
    ) async {
      await pumpTill(
        tester,
        inventory: inventory,
        cart: cart,
        tracking: tracking,
      );

      await tester.tap(find.textContaining('THHN Wire').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to cart'));
      await tester.pumpAndSettle();

      expect(cart.lines, hasLength(1));
      expect(
        cart.lines.single.unit,
        'PC',
        reason: 'a manual pick keeps today\'s behaviour (decision 17)',
      );
    });
  });
}
