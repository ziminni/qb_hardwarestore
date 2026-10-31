@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_shift_page.dart';
import 'package:client/features/pos/widgets/pos_shift_close_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The visual check for card C6 (00-shared/VERIFY.md, fallback 3): the Shifts
/// tab in its open, closed, empty and failed states, with the REAL fonts and the
/// REAL theme, written as PNGs into the SDD folder so the layout can be looked
/// at without a browser.
///
/// Same opt-in mechanism as the shared components' golden test, so the normal
/// suite never fails on a font or platform difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/pos/pos_shift_page_golden_test.dart
/// ```
void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

  // Absolute on purpose: the PNGs belong to the SDD folder of the main
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
    // Peso sign: the bundled OpenSans and Cinzel have no U+20B1, so every
    // amount would be a box. The app relies on the platform font here; the
    // test has none, so a system font that does carry it stands in.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  for (final state in const ['open', 'closed']) {
    for (final entry in const [
      ('1440', Size(1440, 900)),
      ('1100', Size(1100, 900)),
      ('760', Size(760, 900)),
    ]) {
      testWidgets('$state at ${entry.$1} px', (tester) async {
        await _pump(tester, state, entry.$2);
        await expectLater(
          find.byKey(_goldenKey),
          matchesGoldenFile(
            Uri.file('${goldenDir.path}/c6-$state-${entry.$1}.png'),
          ),
        );
      }, skip: !enabled);
    }
  }

  testWidgets('empty at 760 px', (tester) async {
    await _pump(tester, 'empty', const Size(760, 900));
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/c6-empty-760.png')),
    );
  }, skip: !enabled);

  // The Z-reading's second home: the dialog that follows a close, shared with
  // the till. It is inside an AlertDialog, which sizes its content with
  // intrinsics, so it gets its own PNG.
  testWidgets('the close result dialog at 760 px', (tester) async {
    final viewmodel = _viewmodel('open');
    await viewmodel.load();
    tester.view.physicalSize = const Size(760, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _goldenKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme.copyWith(
            textTheme: AppTheme.lightTheme.textTheme.apply(
              fontFamilyFallback: const [_pesoFallbackFamily],
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showShiftCloseDialog(context, viewmodel),
                  child: const Text('Close shift'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close shift'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '35000');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Close shift'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Shift closed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/c6-closed-dialog-760.png')),
    );
  }, skip: !enabled);

  testWidgets('error at 760 px', (tester) async {
    await _pump(tester, 'error', const Size(760, 900));
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/c6-error-760.png')),
    );
  }, skip: !enabled);
}

const _goldenKey = ValueKey('PosShiftGolden');

/// The running reading `GET /shifts/current/` carries while a shift is open: no
/// closing count, so no variance.
const _running = ZReading(
  transactionCount: 26,
  grossSales: 48290,
  cashSales: 24150,
  cardSales: 14500,
  gcashSales: 9640,
  expectedDrawer: 29150,
  variance: null,
  // Two parked baskets: the advisory line has to be seen in the PNG, and it
  // only appears when there is something to warn about.
  heldCartCount: 2,
);

/// Closed readings in all three variance shapes, because short, over and exact
/// have to look different from each other.
const _short = ZReading(
  transactionCount: 34,
  grossSales: 61250,
  cashSales: 31250,
  cardSales: 18000,
  gcashSales: 12000,
  expectedDrawer: 36250,
  variance: -1250,
);

const _over = ZReading(
  transactionCount: 18,
  grossSales: 21000,
  cashSales: 9000,
  cardSales: 7000,
  gcashSales: 5000,
  expectedDrawer: 14000,
  variance: 125.5,
);

Shift _shift({
  required int id,
  required String status,
  required String cashier,
  required DateTime openedAt,
  double openingFloat = 5000,
  double? closingCount,
  ZReading? zReading,
  int heldCarts = 0,
}) {
  return Shift(
    id: id,
    cashierName: cashier,
    status: status,
    openingFloat: openingFloat,
    closingCount: closingCount,
    openedAt: openedAt,
    closedAt: status == Shift.closedStatus
        ? openedAt.add(const Duration(hours: 9))
        : null,
    notes: '',
    zReading: zReading,
    heldCartCount: heldCarts,
  );
}

/// The history the layout has to survive: a SEVEN DIGIT drawer behind a long
/// cashier name, a short drawer, an over drawer, and a row nobody counted yet.
List<Shift> _history() => [
  _shift(
    id: 4,
    status: Shift.closedStatus,
    cashier: 'Ana Cruz',
    openedAt: DateTime(2026, 10, 30, 8),
    closingCount: 35000,
    zReading: _short,
  ),
  _shift(
    id: 3,
    status: Shift.closedStatus,
    cashier: 'Maria Concepcion Dela Cruz Villanueva',
    openedAt: DateTime(2026, 10, 29, 8),
    openingFloat: 1234567.89,
    closingCount: 1234442.39,
    zReading: _over,
  ),
  _shift(
    id: 2,
    status: Shift.closedStatus,
    cashier: 'Ana Cruz',
    openedAt: DateTime(2026, 10, 28, 8),
    closingCount: 5000,
  ),
];

/// Answers from memory; nothing here touches a server.
class _StubShifts extends ShiftService {
  _StubShifts({this.current, this.history = const [], this.failure});

  final Shift? current;
  final List<Shift> history;
  final String? failure;

  @override
  Future<Shift?> fetchCurrent() async {
    final message = failure;
    if (message != null) throw ShiftServiceException(message);
    return current;
  }

  @override
  Future<List<Shift>> fetchAll() async {
    final message = failure;
    if (message != null) throw ShiftServiceException(message);
    return history;
  }

  /// The close the dialog's form posts: the server's own closed copy, reading
  /// and all, so the dialog renders the numbers a cashier would really see.
  @override
  Future<Shift> closeShift(int shiftId, double closingCount) async => _shift(
    id: shiftId,
    status: Shift.closedStatus,
    cashier: 'Ana Cruz',
    openedAt: DateTime(2026, 10, 30, 8),
    closingCount: closingCount,
    zReading: _short,
    heldCarts: 2,
  );
}

ShiftViewmodel _viewmodel(String state) {
  return switch (state) {
    'open' => ShiftViewmodel(
      service: _StubShifts(
        current: _shift(
          id: 5,
          status: Shift.openStatus,
          cashier: 'Ana Cruz',
          openedAt: DateTime(2026, 10, 30, 8),
          zReading: _running,
          heldCarts: 2,
        ),
        history: [
          _shift(
            id: 5,
            status: Shift.openStatus,
            cashier: 'Ana Cruz',
            openedAt: DateTime(2026, 10, 30, 8),
          ),
          ..._history(),
        ],
      ),
    ),
    'closed' => ShiftViewmodel(service: _StubShifts(history: _history())),
    'empty' => ShiftViewmodel(service: _StubShifts()),
    _ => ShiftViewmodel(
      service: _StubShifts(
        failure: 'Cannot connect to the BuildPro server. Try again.',
      ),
    ),
  };
}

Future<void> _pump(WidgetTester tester, String state, Size size) async {
  final viewmodel = _viewmodel(state);
  await viewmodel.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _goldenKey,
      child: ChangeNotifierProvider<AuthViewmodel>.value(
        value: AuthViewmodel(AuthRepository(AuthService())),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          // Only the goldens: lets a peso sign fall back to the system font the
          // app itself uses, because the brand fonts stop at Latin.
          theme: AppTheme.lightTheme.copyWith(
            textTheme: AppTheme.lightTheme.textTheme.apply(
              fontFamilyFallback: const [_pesoFallbackFamily],
            ),
          ),
          home: PosShiftPage(viewmodel: viewmodel),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The logo is an asset image and image decoding does not run inside the fake
  // async zone: without this the brand renders as empty space.
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
  expect(find.byType(Scaffold), findsWidgets);
  expect(
    tester.takeException(),
    isNull,
    reason: 'a layout overflow would paint the yellow stripes into the PNG',
  );
}

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
