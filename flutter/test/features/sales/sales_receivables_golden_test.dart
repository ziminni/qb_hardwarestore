@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/views/pos_receivables_page.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/views/sales_receivables_page.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The visual check for card S2 (00-shared/VERIFY.md, fallback 3): both
/// receivables screens, with the REAL fonts and the REAL theme, written as PNGs
/// into the SDD folder so the layout can be looked at without a browser.
///
/// Same opt-in mechanism as the shared components' golden test, so the normal
/// suite never fails on a font or platform difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/sales/sales_receivables_golden_test.dart
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

  for (final screen in _screens) {
    for (final entry in const [
      ('1440', Size(1440, 900)),
      ('1100', Size(1100, 900)),
      ('760', Size(760, 900)),
    ]) {
      testWidgets('${screen.name} list at ${entry.$1} px', (tester) async {
        await _pump(tester, screen, entry.$2);
        await expectLater(
          find.byKey(_goldenKey),
          matchesGoldenFile(
            Uri.file(
              '${goldenDir.path}/s2-${screen.name}-list-${entry.$1}.png',
            ),
          ),
        );
      }, skip: !enabled);
    }

    testWidgets('${screen.name} empty at 760 px', (tester) async {
      await _pump(tester, screen, const Size(760, 900), rows: const []);
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/s2-${screen.name}-empty-760.png'),
        ),
      );
    }, skip: !enabled);

    testWidgets('${screen.name} error at 760 px', (tester) async {
      await _pump(
        tester,
        screen,
        const Size(760, 900),
        rows: const [],
        failure: 'Cannot connect to the BuildPro server. Try again.',
      );
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/s2-${screen.name}-error-760.png'),
        ),
      );
    }, skip: !enabled);
  }

  // The restyled payment dialog, the one part of the screen a hand types into.
  testWidgets('cashier payment dialog at 760 px', (tester) async {
    await _pump(tester, _screens.first, const Size(760, 900));
    await tester.tap(find.text('Record payment').first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/s2-cashier-dialog-760.png'),
      ),
    );
  }, skip: !enabled);
}

const _goldenKey = ValueKey('SalesReceivablesGolden');

/// The two screens that now share one content widget, by the name their PNGs
/// carry. Each is built around the viewmodel the test provides, so no page
/// reaches a server.
const _screens = [
  _Screen('cashier', PosReceivablesPage.new),
  _Screen('manager', SalesReceivablesPage.new),
];

class _Screen {
  const _Screen(this.name, this.build);

  final String name;
  final Widget Function({Key? key, SalesReceivablesViewmodel? viewmodel}) build;
}

/// Realistic rows covering what the layout must survive: a plain debt due in a
/// month, a SEVEN DIGIT overdue balance behind a long customer name, one due
/// this week, and a part settled account.
List<LedgerEntry> _rows() {
  final today = DateTime(2026, 10, 30);
  return [
    LedgerEntry(
      id: 1,
      customerId: 3,
      customerName: 'Dela Cruz Construction',
      transactionNo: 'TRX-20261016-0001',
      originalAmount: 5000,
      balanceDue: 472,
      dueDate: today.add(const Duration(days: 30)),
      isOverdue: false,
    ),
    LedgerEntry(
      id: 2,
      customerId: 4,
      customerName:
          'Northern Mindanao Builders and Hardware Trading Corporation',
      transactionNo: 'TRX-20261016-0002',
      originalAmount: 1148000,
      balanceDue: 1148000,
      dueDate: today.subtract(const Duration(days: 20)),
      isOverdue: true,
    ),
    LedgerEntry(
      id: 3,
      customerId: 5,
      customerName: 'Reyes Trading',
      transactionNo: 'TRX-20261016-0003',
      originalAmount: 9000,
      balanceDue: 9000,
      dueDate: appClock.now().add(const Duration(days: 3)),
      isOverdue: false,
    ),
    LedgerEntry(
      id: 4,
      customerId: 6,
      customerName: 'Bunawan Hardware',
      transactionNo: 'TRX-20261016-0004',
      originalAmount: 2400,
      balanceDue: 1200,
      dueDate: today.add(const Duration(days: 45)),
      isOverdue: false,
    ),
  ];
}

/// Answers from memory; nothing here touches a server.
class _StubLedgerRepository extends LedgerRepository {
  _StubLedgerRepository({required this.rows, this.failure});

  final List<LedgerEntry> rows;
  final String? failure;

  @override
  Future<List<LedgerEntry>> fetchLedgers() async {
    final message = failure;
    if (message != null) throw LedgerServiceException(message);
    return rows;
  }

  @override
  Future<void> recordPayment({
    required int collectibleId,
    required double amountPaid,
    TenderMethod method = TenderMethod.cash,
    String? officialReceiptNo,
  }) async {}
}

SalesReceivablesViewmodel _viewmodel({
  List<LedgerEntry>? rows,
  String? failure,
}) {
  return SalesReceivablesViewmodel(
    repository: _StubLedgerRepository(rows: rows ?? _rows(), failure: failure),
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Screen screen,
  Size size, {
  List<LedgerEntry>? rows,
  String? failure,
}) async {
  final viewmodel = _viewmodel(rows: rows, failure: failure);
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
          home: screen.build(viewmodel: viewmodel),
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
