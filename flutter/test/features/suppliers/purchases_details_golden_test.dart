@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/suppliers/widgets/purchases_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner review material for Task 10b (phase 1d): the redesigned purchase order
/// details dialog, with three lines in three units and the "Received x / y
/// lines" summary, painted with the REAL fonts.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/suppliers/purchases_details_golden_test.dart
/// ```
void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');
  final goldenDir = Directory(
    '${Directory.current.path}/../.superpowers/sdd/ui-refresh/goldens',
  );

  setUpAll(() async {
    goldenDir.createSync(recursive: true);
    await _loadFont('Cinzel', const [
      'Cinzel-Regular.ttf',
      'Cinzel-Medium.ttf',
      'Cinzel-Bold.ttf',
    ]);
    await _loadFont('OpenSans', const [
      'OpenSans-Regular.ttf',
      'OpenSans-Medium.ttf',
      'OpenSans-Bold.ttf',
    ]);
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
    // The brand fonts stop at Latin, so the peso sign would be a box.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  for (final (width, scale) in const [
    (1440.0, 1.0),
    (1100.0, 1.0),
    (760.0, 1.3),
  ]) {
    testWidgets('purchase order details at ${width.toInt()} px, '
        'text scale $scale', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        RepaintBoundary(
          key: goldenKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme.copyWith(
              textTheme: AppTheme.lightTheme.textTheme.apply(
                fontFamilyFallback: const [_pesoFallbackFamily],
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              backgroundColor: const Color(0xFFF8F6F0),
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) =>
                          PurchasesDetailsDialog(order: _partOrder()),
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Received 1 / 3 lines'), findsOneWidget);

      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
          Uri.file(
            '${goldenDir.path}/t10b_po_details_${width.toInt()}_'
            '${scale.toStringAsFixed(1).replaceAll('.', '_')}.png',
          ),
        ),
      );
    }, skip: !enabled);
  }
}

const goldenKey = ValueKey('PurchasesDetailsGolden');

/// A partly received order: a bag line complete, a steel line half in, a pipe
/// line untouched. Three units, so no total may be summed.
PurchaseOrder _partOrder() => PurchaseOrder(
  id: 41,
  supplierId: 9,
  supplierName: 'Cebu Steel Works and General Merchandise Incorporated',
  orderDate: DateTime(2026, 10, 20),
  expectedDelivery: DateTime(2026, 10, 25),
  status: PurchaseStatus.partial,
  createdBy: 'Ana Lopez',
  notes:
      'Second delivery expected. Call the supplier the day before the truck '
      'leaves Mandaue.',
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

const String _pesoFallbackFamily = 'PesoFallback';

const List<String> _pesoFontCandidates = [
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  '/usr/share/fonts/TTF/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  'C:/Windows/Fonts/arial.ttf',
];

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = await File('assets/fonts/$file').readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _loadFontFile(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

String? _flutterSdkFile(String relativePath) {
  final candidates = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?)
      '$root/$relativePath',
  ];
  var dir = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 6; depth++) {
    candidates.add('${dir.path}/$relativePath');
    dir = dir.parent;
  }
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
