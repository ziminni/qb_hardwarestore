@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Owner review material for Task 10b (phase 1d): the shared transaction and
/// return document sheet with its hexagon header and gold total bar, painted
/// with the REAL fonts, at 1440, 1100 and 760 px (1.3x text at the narrow one).
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/sales/sales_document_sheet_golden_test.dart
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
    testWidgets('document sheet at ${width.toInt()} px, text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
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
                    onPressed: () => showSalesDocumentSheet(
                      context,
                      title: 'TRX-20261030-0002',
                      fields: _fields,
                      lines: _lines,
                      total: 1149600,
                    ),
                    child: const Text('View'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(find.byType(SalesDocumentSheet), findsOneWidget);

      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
          Uri.file(
            '${goldenDir.path}/t10b_document_sheet_${width.toInt()}_'
            '${scale.toStringAsFixed(1).replaceAll('.', '_')}.png',
          ),
        ),
      );
    }, skip: !enabled);
  }
}

const goldenKey = ValueKey('DocumentSheetGolden');

const _fields = <(String, String)>[
  ('Date', 'Oct 30, 2026'),
  ('Customer', 'Reyes Trading'),
  ('Cashier', 'Ana Lopez'),
  ('Status', 'Completed'),
];

const _lines = <SalesDocumentLine>[
  SalesDocumentLine(name: 'Portland Cement 40kg', qty: 1200, unitPrice: 950),
  SalesDocumentLine(name: '10 mm x 6 m', qty: 40, unitPrice: 240),
  SalesDocumentLine(
    name: 'Deformed Steel Bar 10 mm x 6 m Grade 60 (cut and bent to schedule)',
    qty: 12,
    unitPrice: 240,
  ),
];

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
