// Product image lane: what the clerk SEES after picking, and what the form does
// with a refused pick.
//
// A picked file has no URL yet — it is bytes in memory — so the preview must be
// an in-memory image (no device path in `Image.network`, none in the payload).
// The dialog also has to survive the two failures the picker reports: an
// oversized file and a cancelled pick.

import 'dart:typed_data';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product_image_upload.dart';
import 'package:client/data/services/image_file_service.dart';
import 'package:client/features/products/widgets/products_form_dialog.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1x1 PNG: the smallest thing `Image.memory` can decode.
final _pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// A picker handing back one image, or a picker that refuses.
ImageFileService _picker(ProductImageUpload? upload, {String? error}) =>
    ImageFileService(
      pickFile: () async {
        if (error != null) throw ImageFileException(error);
        return XFile('/tmp/picked.png');
      },
      onRead: upload == null ? null : (_) async => upload,
    );

/// A picker the clerk cancelled in.
ImageFileService _cancelled() => ImageFileService(pickFile: () async => null);

void main() {
  testWidgets('ProductsImage renders picked bytes without a URL', (
    tester,
  ) async {
    _openWindow(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Center(
          child: ProductsImage(imageBytes: _pngBytes, width: 40, height: 40),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
    expect(image.image, isNot(isA<NetworkImage>()));
  });

  testWidgets('ProductsImage still shows a placeholder with nothing to draw', (
    tester,
  ) async {
    _openWindow(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Center(child: ProductsImage(imageUrl: '')),
      ),
    );

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('picking a photo previews it in memory and names the file', (
    tester,
  ) async {
    _openWindow(tester);
    await tester.pumpWidget(
      _hostDialog(
        _picker(
          ProductImageUpload(bytes: _pngBytes, filename: 'sack.png'),
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose image'));
    await tester.pumpAndSettle();

    expect(find.text('sack.png'), findsOneWidget);
    expect(find.text('Replace image'), findsOneWidget);
    expect(
      tester.widget<Image>(find.byType(Image)).image,
      isA<MemoryImage>(),
    );
  });

  testWidgets('an oversized pick is explained and changes nothing', (
    tester,
  ) async {
    _openWindow(tester);
    await tester.pumpWidget(
      _hostDialog(
        _picker(
          null,
          error: 'That image is larger than 5 MB. Choose a smaller photo.',
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose image'));
    await tester.pumpAndSettle();

    expect(find.textContaining('larger than 5 MB'), findsOneWidget);
    expect(find.text('No image selected'), findsOneWidget);
    expect(find.text('Choose image'), findsOneWidget);
  });

  testWidgets('a cancelled pick leaves the picker untouched', (tester) async {
    _openWindow(tester);
    await tester.pumpWidget(_hostDialog(_cancelled()));
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose image'));
    await tester.pumpAndSettle();

    expect(find.text('No image selected'), findsOneWidget);
  });
}

/// A window tall enough for the whole form: the image picker sits below the
/// fold in the default 800x600 test window.
void _openWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The dialog inside a Scaffold, opened by a button — the same shape the products
/// page uses.
Widget _hostDialog(ImageFileService service) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showDialog<ProductFormResult>(
              context: context,
              builder: (_) => ProductsFormDialog(
                categories: const [Category(id: 1, name: 'Cement')],
                brands: const [Brand(id: 1, name: 'Holcim')],
                units: const [UnitOfMeasure(id: 1, code: 'KG', name: 'Kilogram')],
                products: const [],
                imageFileService: service,
              ),
            ),
            child: const Text('Open form'),
          ),
        ),
      ),
    ),
  );
}
