@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/features/inventory/views/inventory_returns_page.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/inventory_returns_fixtures.dart';
import '../../support/transactions_fixtures.dart';

/// The fallback visual check (00-shared/VERIFY.md, fallback 3) for card K9: the
/// stock manager's Returns screen, rendered with the REAL fonts and the REAL
/// theme, written as PNGs into the SDD folder so the layout can be looked at
/// without a browser.
///
/// Same opt-in mechanism as the F3, F4 and S1 golden tests, so the normal suite
/// never fails on a font or platform difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/inventory/inventory_returns_golden_test.dart
/// ```
void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

  // Absolute on purpose: the PNGs belong to the SDD folder in the main
  // checkout, not next to this test inside the card's worktree.
  final goldenDir = Directory(
    '/home/yaji/projects/qb_ecosystem/qb_pos_inventory_system/'
    '.superpowers/sdd/ui-refresh/goldens',
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
    // Icons: the test harness does not load the Material icon font, so every
    // Icon would be a box in the PNG.
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
    // Peso sign: the bundled OpenSans and Cinzel have no U+20B1, so every amount
    // would be a box. The app relies on the platform font here; the test has
    // none, so a system font that does carry it stands in.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  for (final entry in const [
    ('1440', Size(1440, 900)),
    ('1100', Size(1100, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('returns list at ${entry.$1} px', (tester) async {
      await _pump(
        tester,
        entry.$2,
        InventorySalesViewmodel(
          service: StubSalesService(rows: inventoryReturnsFixture()),
        ),
      );
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/k9-list-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('returns empty at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      InventorySalesViewmodel(service: StubSalesService()),
    );
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/k9-empty-760.png')),
    );
  }, skip: !enabled);

  testWidgets('returns error at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      InventorySalesViewmodel(
        service: StubSalesService(
          error: 'The returns list could not be loaded. Try again.',
        ),
      ),
    );
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/k9-error-760.png')),
    );
  }, skip: !enabled);
}

const _goldenKey = ValueKey('InventoryReturnsGolden');

const String _pesoFallbackFamily = 'PesoFallback';

const List<String> _pesoFontCandidates = [
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  '/usr/share/fonts/TTF/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  'C:/Windows/Fonts/arial.ttf',
];

Future<void> _pump(
  WidgetTester tester,
  Size size,
  InventorySalesViewmodel viewmodel,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _goldenKey,
      child: transactionsApp(
        child: const InventoryReturnsPage(),
        viewmodel: viewmodel,
        // Only the goldens: lets a peso sign fall back to the system font the
        // app itself uses, because the brand fonts stop at Latin.
        theme: AppTheme.lightTheme.copyWith(
          textTheme: AppTheme.lightTheme.textTheme.apply(
            fontFamilyFallback: const [_pesoFallbackFamily],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // A layout overflow would paint yellow stripes into the PNG; a throw here
  // names it instead of shipping it.
  expect(tester.takeException(), isNull);
}

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

/// The running Flutter SDK, found from the environment or from the dart binary
/// that is executing this test.
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
