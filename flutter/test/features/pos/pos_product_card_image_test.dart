import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_product_browser.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

void main() {
  test('PosTransactionViewmodel copies product.imageUrl onto PosCatalogItem', () {
    const photoUrl = 'http://127.0.0.1:8000/media/product-images/cement.jpg';
    const product = Product(
      id: 10,
      baseName: 'Portland Cement',
      description: '',
      categoryId: 1,
      categoryName: 'Cement',
      brandId: 1,
      brandName: 'Holcim',
      imageUrl: photoUrl,
      isActive: true,
      variants: [
        ProductVariant(
          id: 101,
          productId: 10,
          baseUomId: 1,
          minStockThreshold: 5,
          maxStockLevel: 100,
          variantName: '40kg Bag',
          baseUomCode: 'BAG',
          isActive: true,
          sellingUoms: [
            VariantUom(
              id: 1001,
              variantId: 101,
              uomId: 1,
              uomCode: 'BAG',
              uomName: 'Bag',
              conversionFactor: 1,
              defaultSellingPrice: 260,
              barcodeQr: 'QB-1001',
              uomIsWhole: true,
            ),
          ],
        ),
      ],
    );

    final lots = [batch(id: 1, variantId: 101, qty: 20, cost: 220, receiptId: 1)];
    final inventory = InventoryViewmodel.seeded(
      catalogue: FakeProductsRepository(products: [product], batches: lots),
      inventory: FakeInventoryRepository(),
      catalogueLists: FakeCatalogueRepository(),
      products: [product],
      batches: lots,
      stockOnHand: onHandFromBatches(lots),
    );
    final cart = PosTransactionViewmodel(inventory);
    addTearDown(cart.dispose);

    expect(cart.filteredProducts, hasLength(1));
    expect(cart.filteredProducts.first.imageUrl, photoUrl);
  });

  testWidgets(
    'material cards show a placeholder when empty and the stocker image when present',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Write a tiny valid 1x1 PNG to a temp file so Image.file loads locally
      // without needing HTTP in the widget test.
      final tempDir = Directory.systemTemp.createTempSync('pos_card_img_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final imgFile = File('${tempDir.path}/cement.png')
        ..writeAsBytesSync(const <int>[
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
          0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
          0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
          0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
          0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89,
          0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
          0xAE, 0x42, 0x60, 0x82,
        ]);

      final search = TextEditingController();
      final focus = FocusNode();
      addTearDown(search.dispose);
      addTearDown(focus.dispose);

      final items = [
        PosCatalogItem(
          variantUomId: 1,
          variantId: 1,
          productName: 'Portland Cement',
          variantName: '40kg Bag',
          unit: 'BAG',
          barcode: 'QB-1',
          conversionFactor: 1,
          unitPrice: 260,
          availableBaseStock: 50,
          categoryName: 'Cement',
          imageUrl: imgFile.path,
        ),
        const PosCatalogItem(
          variantUomId: 2,
          variantId: 2,
          productName: 'Marine Plywood',
          variantName: '1/2 inch',
          unit: 'SHEET',
          barcode: 'QB-2',
          conversionFactor: 1,
          unitPrice: 980,
          availableBaseStock: 12,
          categoryName: 'Wood',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: PosProductBrowser(
              products: items,
              onSearch: (_) {},
              onSelect: (_) {},
              searchController: search,
              searchFocusNode: focus,
              onSubmitted: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both cards render a ProductsImage thumbnail/banner.
      final images = tester
          .widgetList<ProductsImage>(find.byType(ProductsImage))
          .toList();
      expect(images, hasLength(2));
      expect(images[0].imageUrl, imgFile.path);
      expect(images[1].imageUrl, isEmpty);

      // The card without a photo shows the image placeholder icon.
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      // The card with a photo renders a real Image widget.
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets(
    'material cards render a square photo and keep price tight beneath stock badge',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final search = TextEditingController();
      final focus = FocusNode();
      addTearDown(search.dispose);
      addTearDown(focus.dispose);

      const items = [
        PosCatalogItem(
          variantUomId: 1,
          variantId: 1,
          productName: 'Faucet',
          variantName: 'Standard',
          unit: 'PC',
          barcode: 'QB-10',
          conversionFactor: 1,
          unitPrice: 225,
          availableBaseStock: 93,
          categoryName: 'Plumbing',
          brandName: 'FlowPro',
        ),
        PosCatalogItem(
          variantUomId: 2,
          variantId: 2,
          productName: 'Heavy Duty Galvanized Steel Pipe Fitting',
          variantName: '1/2 inch',
          unit: 'PC',
          barcode: 'QB-11',
          conversionFactor: 1,
          unitPrice: 1480.5,
          availableBaseStock: 12,
          categoryName: 'Plumbing',
          brandName: 'FlowPro',
        ),
      ];

      // Test in a typical till left-pane width (~640px) where cards stack.
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                height: 800,
                child: PosProductBrowser(
                  products: items,
                  onSearch: (_) {},
                  onSelect: (_) {},
                  searchController: search,
                  searchFocusNode: focus,
                  onSubmitted: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The photo header on each card must be square (1:1 aspect ratio).
      final firstImageSize = tester.getSize(find.byType(ProductsImage).first);
      expect(
        (firstImageSize.width - firstImageSize.height).abs(),
        lessThanOrEqualTo(1.0),
        reason:
            'POS card image should be square, got '
            '${firstImageSize.width}x${firstImageSize.height}',
      );

      // Stock badge and price sit tightly together with no dead vertical gap.
      final stockRect = tester.getRect(find.text('93 pc in stock'));
      final priceRect = tester.getRect(find.textContaining('225.00'));
      final gap = priceRect.top - stockRect.bottom;
      expect(
        gap,
        inInclusiveRange(0.0, 24.0),
        reason:
            'Expected tight spacing between stock badge and price, got ${gap}px',
      );
    },
  );
}
