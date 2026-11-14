@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/features/pos/views/pos_transaction_history_page.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/views/inventory_sales_page.dart';
import 'package:client/features/sales/views/sales_transactions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/transactions_fixtures.dart';

/// The fallback visual check (00-shared/VERIFY.md, fallback 3) for card S1: the
/// three Transactions screens, rendered with the REAL fonts and the REAL theme,
/// written as PNGs into the SDD folder so the layout can be looked at without a
/// browser.
///
/// Same opt-in mechanism as F3's and F4's golden tests, so the normal suite never
/// fails on a font or platform difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/sales/sales_transactions_golden_test.dart
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

  for (final screen in _screens) {
    for (final entry in const [
      ('1440', Size(1440, 900)),
      ('1100', Size(1100, 900)),
      ('760', Size(760, 900)),
    ]) {
      testWidgets('${screen.name} list at ${entry.$1} px', (tester) async {
        await _pump(tester, screen, entry.$2, _loaded());
        await expectLater(
          find.byKey(_goldenKey),
          matchesGoldenFile(
            Uri.file(
              '${goldenDir.path}/s1-${screen.name}-list-${entry.$1}.png',
            ),
          ),
        );
      }, skip: !enabled);
    }

    testWidgets('${screen.name} empty at 760 px', (tester) async {
      await _pump(
        tester,
        screen,
        const Size(760, 900),
        InventorySalesViewmodel(service: StubSalesService()),
      );
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/s1-${screen.name}-empty-760.png'),
        ),
      );
    }, skip: !enabled);

    testWidgets('${screen.name} error at 760 px', (tester) async {
      await _pump(
        tester,
        screen,
        const Size(760, 900),
        InventorySalesViewmodel(
          service: StubSalesService(
            error: 'The sales list could not be loaded. Try again.',
          ),
        ),
      );
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/s1-${screen.name}-error-760.png'),
        ),
      );
    }, skip: !enabled);
  }
}

const _goldenKey = ValueKey('SalesTransactionsGolden');

InventorySalesViewmodel _loaded() => InventorySalesViewmodel(
  service: StubSalesService(rows: transactionsFixture()),
);

/// The three role screens, by the name their PNGs carry.
const _screens = [
  _Screen('cashier', PosTransactionHistoryPage()),
  _Screen('manager', SalesTransactionsPage()),
  _Screen('stock', InventorySalesPage()),
];

class _Screen {
  const _Screen(this.name, this.page);

  final String name;
  final Widget page;
}

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
  _Screen screen,
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
        child: screen.page,
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
  // The logo is an asset image and image decoding does not run inside the fake
  // async zone: without this the brand renders as empty space. 42 is the full
  // sidebar's size, 40 the rail's.
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(_goldenKey));
    for (final size in const [40, 42]) {
      await precacheImage(
        ResizeImage.resizeIfNeeded(
          size,
          size,
          const AssetImage(AppAssets.logo),
        ),
        context,
      );
    }
  });
  await tester.pumpAndSettle();
  // A page that scrolled to keep its focus is not what the reader sees.
  expect(find.byType(Scaffold), findsWidgets);
  expect(
    tester.takeException(),
    isNull,
    reason: 'a layout overflow would paint the yellow stripes into the PNG',
  );
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
