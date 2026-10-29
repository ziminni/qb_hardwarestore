// Phase 6 Task 7 (decision 18): every selling unit's code, and who may edit it.
//
// The details dialog showed `Barcode: ${variant.barcode}` — the variant's FIRST
// non-blank code. A box of 100 and the piece it contains therefore looked like one
// row with one code, and the box's code was invisible (Barcode baseline F3).

import 'package:client/data/models/product.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/widgets/edit_unit_code_dialog.dart';
import 'package:client/features/products/widgets/products_details_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// A variant sold by the piece (QB000012-3) and by the box of 100 (QB000013-0).
Product twoUnitProduct() => product(
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
          barcodeQr: 'QB000012-3',
          conversionFactor: 1,
          defaultSellingPrice: 20,
        ),
        VariantUom(
          id: 130,
          variantId: 12,
          uomId: 2,
          uomCode: 'BOX',
          uomName: 'Box of 100',
          barcodeQr: 'QB000013-0',
          conversionFactor: 100,
          defaultSellingPrice: 1900,
        ),
      ],
    ),
  ],
);

/// The shape QA hit at 1366×768: five variants, each with two units, in a dialog
/// that has to fit a real laptop viewport (`qa-browser-assets/e10-*`).
Product fiveVariantProduct() => product(
  id: 40,
  name: 'QA Integrity Item',
  variants: [
    for (var index = 0; index < 5; index++)
      variant(
        id: 400 + index,
        productId: 40,
        name: 'Variant ${index + 1}',
        baseUomCode: 'PC',
        sellingUoms: [
          VariantUom(
            id: 4000 + index * 2,
            variantId: 400 + index,
            uomId: 1,
            uomCode: 'PC',
            uomName: 'Piece',
            barcodeQr: 'QB00004$index-1',
            conversionFactor: 1,
            defaultSellingPrice: 315,
          ),
          VariantUom(
            id: 4001 + index * 2,
            variantId: 400 + index,
            uomId: 2,
            uomCode: 'QABOX',
            uomName: 'QA Box',
            barcodeQr: 'QB00004$index-2',
            conversionFactor: 12,
            defaultSellingPrice: 3000,
          ),
        ],
      ),
  ],
);

AuthViewmodel authWithRole(String? roleCode) {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth.user = User(
    id: 1,
    username: 'ana',
    email: 'ana@example.com',
    fullName: 'Ana Cruz',
    role: roleCode == null
        ? null
        : Role(id: 1, name: roleCode, displayName: roleCode),
  );
  return auth;
}

void main() {
  late FakeProductsRepository repository;
  late InventoryViewmodel inventory;
  late Product product2;

  setUp(() {
    product2 = twoUnitProduct();
    repository = FakeProductsRepository(
      products: [product2],
      batches: [batch(id: 1, variantId: 12, qty: 500)],
    );
    inventory = InventoryViewmodel.seeded(
      catalogue: repository,
      inventory: FakeInventoryRepository(),
      catalogueLists: FakeCatalogueRepository(),
      products: [product2],
      batches: [batch(id: 1, variantId: 12, qty: 500)],
    );
  });

  Future<void> openDetails(WidgetTester tester, String? roleCode) async {
    // The dialog is 780 wide and its content scrolls; at the default 800x600 test
    // surface the unit rows sit below the fold and a tap cannot reach them.
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: authWithRole(roleCode),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ProductsDetailsDialog(product: product2),
                ),
                child: const Text('open details'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open details'));
    await tester.pumpAndSettle();
  }

  testWidgets('lists the code of EVERY selling unit', (tester) async {
    await openDetails(tester, 'inventory');

    expect(find.textContaining('QB000012-3'), findsOneWidget);
    expect(
      find.textContaining('QB000013-0'),
      findsOneWidget,
      reason: 'the box carries its own code and must be visible',
    );
    // The unit and its factor travel with the code: a code with no unit is unusable.
    expect(find.textContaining('BOX'), findsWidgets);
  });

  testWidgets(
    'at 1366x768 the LAST unit scrolls into view and its Edit code still works',
    (tester) async {
      // QA defect 4: the content overflowed the viewport with no working scroll, so
      // selling units of the lower variants were unreachable at the target size.
      final wideProduct = fiveVariantProduct();
      final wideInventory = InventoryViewmodel.seeded(
        products: [wideProduct],
        batches: [batch(id: 9, variantId: 400, qty: 100)],
      );
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<InventoryViewmodel>.value(
              value: wideInventory,
            ),
            ChangeNotifierProvider<AuthViewmodel>.value(
              value: authWithRole('inventory'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ProductsDetailsDialog(product: wideProduct),
                  ),
                  child: const Text('open details'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open details'));
      await tester.pumpAndSettle();

      // The QA finding: at 1366x768 the lower units were unreachable with a MOUSE
      // — a wheel over the dialog did not move the content and no scrollbar was
      // visible to grab (`qa-browser-assets/e10-dialog-1366x768.png`).
      final scrollbar = find.descendant(
        of: find.byType(ProductsDetailsDialog),
        matching: find.byType(Scrollbar),
      );
      expect(
        scrollbar,
        findsOneWidget,
        reason: 'the dialog must show a scrollbar the clerk can see and grab',
      );
      expect(
        tester.widget<Scrollbar>(scrollbar).thumbVisibility,
        isTrue,
        reason:
            'a hover-only thumb is invisible on a plain mouse until you hover',
      );

      final scrollable = find
          .descendant(
            of: find.byType(ProductsDetailsDialog),
            matching: find.byType(Scrollable),
          )
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.pixels, 0);

      // A real mouse wheel over the dialog, the way a user scrolls it.
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.byType(ProductsDetailsDialog))),
      );
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 400)));
      await tester.pumpAndSettle();

      expect(
        position.pixels,
        greaterThan(0),
        reason:
            'the wheel must scroll the dialog content, not the page behind it',
      );

      final lastCode = find.textContaining('QB000044-2');
      await tester.scrollUntilVisible(lastCode, 200, scrollable: scrollable);
      await tester.pumpAndSettle();

      expect(
        lastCode,
        findsOneWidget,
        reason: "the fifth variant's QA-box code must be reachable",
      );
      await tester.tap(find.text('Edit code').last);
      await tester.pumpAndSettle();

      expect(
        find.byType(EditUnitCodeDialog),
        findsOneWidget,
        reason: 'a reachable row must still be operable',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'no RenderFlex overflow at 1366x768',
      );
    },
  );

  testWidgets('a cashier sees the codes but no Edit code button', (
    tester,
  ) async {
    await openDetails(tester, 'pos');

    expect(find.textContaining('QB000013-0'), findsOneWidget);
    expect(
      find.text('Edit code'),
      findsNothing,
      reason: 'code writes are inventory roles only (decision 18)',
    );
  });

  testWidgets('an inventory role gets an Edit code button per unit', (
    tester,
  ) async {
    await openDetails(tester, 'admin');

    expect(find.text('Edit code'), findsNWidgets(2));
  });

  testWidgets('editing a code PATCHes it and reloads the catalogue', (
    tester,
  ) async {
    await openDetails(tester, 'inventory');
    final loadsBefore = repository.loadCount;

    await tester.tap(find.text('Edit code').last);
    await tester.pumpAndSettle();
    // The edit dialog's field is a plain TextField (one field, one value).
    await tester.enterText(find.byType(TextField), '4800016123450');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // The LAST unit is the box (id 130), which is what `.last` tapped.
    expect(repository.barcodePatches, [
      (unitId: 130, barcode: '4800016123450'),
    ]);
    expect(repository.loadCount, loadsBefore + 1);
  });

  testWidgets('a refused code stays on the field and reloads nothing', (
    tester,
  ) async {
    // The server's BARCODE_TAKEN detail names the holder, so it is shown as-is.
    repository.barcodeError =
        'QB000013-0 is already the code of Copper Wire · THHN 3.5mm · BOX.';
    await openDetails(tester, 'inventory');
    final loadsBefore = repository.loadCount;

    await tester.tap(find.text('Edit code').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'QB000013-0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.textContaining('is already the code of'), findsOneWidget);
    expect(
      find.byType(EditUnitCodeDialog),
      findsOneWidget,
      reason:
          'closing would leave the clerk with a message and no way to fix it',
    );
    expect(
      repository.loadCount,
      loadsBefore,
      reason: 'a refused write changed nothing, so there is nothing to reload',
    );
  });

  testWidgets('a blank submit sends a blank code, which restores the QB code', (
    tester,
  ) async {
    await openDetails(tester, 'inventory');
    final loadsBefore = repository.loadCount;

    await tester.tap(find.text('Edit code').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repository.barcodePatches, [
      (unitId: 130, barcode: ''),
    ], reason: 'the server re-derives the unit\'s own QB code from a blank');
    expect(repository.loadCount, loadsBefore + 1);
    expect(find.byType(EditUnitCodeDialog), findsNothing);
  });
}
