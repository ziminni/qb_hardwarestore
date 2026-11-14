@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/held_cart.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/views/pos_held_transactions_page.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The fallback visual check for card C5 (00-shared/VERIFY.md, fallback 3):
/// the held-transactions screen with the REAL fonts, written as PNGs into the
/// SDD folder so the cards can be looked at without a browser.
///
/// Same opt-in mechanism as `components_golden_test.dart`: it only runs when
/// RUN_GOLDENS is passed, so the normal suite never fails on a font or platform
/// difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/pos/pos_held_transactions_page_golden_test.dart
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
    // Icons: the test harness does not load the Material icon font, so every
    // Icon would be a box in the PNG.
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
    // Peso sign: the bundled OpenSans and Cinzel have no U+20B1, so every
    // amount would be a box. The app falls back to the platform font here; the
    // test has none, so a system font that does carry it stands in.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  // Three widths plus the two states that have their own layout.
  for (final entry in const [
    ('1440', Size(1440, 900)),
    ('1100', Size(1100, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('held transactions at ${entry.$1} px', (tester) async {
      await _pump(tester, entry.$2, _CartsFake(_baskets));
      await _capture(tester, '${goldenDir.path}/c5-list-${entry.$1}.png');
    }, skip: !enabled);
  }

  testWidgets('held transactions empty at 760 px', (tester) async {
    await _pump(tester, const Size(760, 900), _CartsFake(const []));
    await _capture(tester, '${goldenDir.path}/c5-empty-760.png');
  }, skip: !enabled);

  testWidgets('held transactions error at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      _CartsFake(
        const [],
        failure: const HeldCartServiceException(
          'Cannot connect to the BuildPro server.',
        ),
      ),
    );
    await _capture(tester, '${goldenDir.path}/c5-error-760.png');
  }, skip: !enabled);
}

const _galleryKey = ValueKey('HeldTransactionsGallery');

const String _pesoFallbackFamily = 'PesoFallback';

const List<String> _pesoFontCandidates = [
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  '/usr/share/fonts/TTF/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  'C:/Windows/Fonts/arial.ttf',
];

/// Answers the page's one read, so no PNG depends on a server.
class _CartsFake extends HeldCartService {
  _CartsFake(this.carts, {this.failure});

  final List<HeldCart> carts;
  final Object? failure;

  @override
  Future<List<HeldCart>> fetchAll() async {
    if (failure != null) throw failure!;
    return carts;
  }
}

/// Realistic parked baskets: a contractor's order, a second one whose total
/// runs to seven digits, and two small ones. The long customer name and the
/// seven digit total are the two values that used to clip.
List<HeldCart> get _baskets {
  final now = appClock.now();
  return [
    HeldCart(
      id: 1,
      customerId: 11,
      customerName: 'Dela Cruz Construction',
      cashierName: 'Ana Cruz',
      notes: 'Pay tomorrow, the foreman will collect',
      items: const [
        HeldCartItem(id: 11, variantUom: 5, qty: 120, unitPrice: 285),
        HeldCartItem(id: 12, variantUom: 9, qty: 48, unitPrice: 540.5),
      ],
      createdAt: now.subtract(const Duration(minutes: 12)),
    ),
    HeldCart(
      id: 2,
      customerId: 12,
      customerName: 'San Miguel Builders and Hardware Supply Incorporated',
      cashierName: 'Ana Cruz',
      notes: '',
      items: const [
        HeldCartItem(id: 21, variantUom: 14, qty: 850, unitPrice: 1452.35),
      ],
      createdAt: now.subtract(const Duration(hours: 1)),
    ),
    HeldCart(
      id: 3,
      customerId: null,
      customerName: null,
      cashierName: 'Ana Cruz',
      notes: '',
      items: const [HeldCartItem(id: 31, variantUom: 3, qty: 2, unitPrice: 74)],
      createdAt: now.subtract(const Duration(hours: 4)),
    ),
    HeldCart(
      id: 4,
      customerId: 13,
      customerName: 'Maria Santos',
      cashierName: 'Ana Cruz',
      notes: 'Reserved for Saturday',
      items: const [
        HeldCartItem(id: 41, variantUom: 7, qty: 6, unitPrice: 1240),
      ],
      createdAt: now.subtract(const Duration(days: 2)),
    ),
  ];
}

Future<void> _pump(
  WidgetTester tester,
  Size size,
  HeldCartService service,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        // The real theme, with the peso fallback the app gets from the platform.
        theme: AppTheme.lightTheme.copyWith(
          textTheme: AppTheme.lightTheme.textTheme.apply(
            fontFamilyFallback: const [_pesoFallbackFamily],
          ),
        ),
        home: RepaintBoundary(
          key: _galleryKey,
          child: ColoredBox(
            color: AppColors.background,
            child: PosHeldTransactionsPage(
              viewmodel: HeldCartViewmodel(service: service),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The logo is an asset image, and image decoding does not run inside the fake
  // async zone: without this the brand renders as empty space.
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(_galleryKey));
    for (final logoSize in const [40, 42]) {
      await precacheImage(
        ResizeImage.resizeIfNeeded(
          logoSize,
          logoSize,
          const AssetImage(AppAssets.logo),
        ),
        context,
      );
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _capture(WidgetTester tester, String path) async {
  await expectLater(find.byKey(_galleryKey), matchesGoldenFile(Uri.file(path)));
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
