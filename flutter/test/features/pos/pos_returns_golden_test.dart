@Tags(['golden'])
library;

// C7 visual check: the Returns screen with the REAL fonts, written as PNGs so
// the layout can be looked at without a browser (00-shared/VERIFY.md, fallback 3).
//
// Opt in, like `test/shared/widgets/components_golden_test.dart`:
//
//   flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
//     test/features/pos/pos_returns_golden_test.dart
//
// States: find (nothing searched yet), choose (a sale found, quantities stepped),
// refund (reason written, Confirm armed), done (the server's posted refund), and
// an error at 760 px. Every width the brief names: 1440, 1100, 760.

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/returns_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/returns_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_returns_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_returns_page.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// The SDD folder, as an ABSOLUTE path: this test runs in a worktree, where
/// `flutter/../.superpowers` is the worktree's own folder, not the shared one.
/// shortcut: machine specific path per the card brief, upgrade if the repo moves.
const String _goldenDir =
    '/home/yaji/projects/qb_ecosystem/qb_pos_inventory_system'
    '/.superpowers/sdd/ui-refresh/goldens';

const ValueKey _rootKey = ValueKey('c7-returns-root');

void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

  setUpAll(() async {
    Directory(_goldenDir).createSync(recursive: true);
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
    // The brand fonts stop at Latin, so the peso sign needs the same system
    // fallback the app itself uses.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile('PesoFallback', candidate);
        break;
      }
    }
  });

  for (final width in const [1440, 1100, 760]) {
    testWidgets('find at $width px', (tester) async {
      await _pump(tester, width);
      await _capture('c7-find-$width.png');
    }, skip: !enabled);

    testWidgets('choose at $width px', (tester) async {
      await _pump(tester, width);
      await _search(tester);
      await _step(tester, line: 'Portland', times: 2);
      await _revealChoices(tester, width);
      await _capture('c7-choose-$width.png');
    }, skip: !enabled);

    testWidgets('refund at $width px', (tester) async {
      await _pump(tester, width);
      await _search(tester);
      await _step(tester, line: 'Portland', times: 10);
      await _step(tester, line: 'Marine', times: 2);
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason for the return (required)'),
        'Two bags split in transit, plywood corners chipped.',
      );
      await tester.pumpAndSettle();
      await _revealChoices(tester, width);
      await _capture('c7-refund-$width.png');
    }, skip: !enabled);

    testWidgets('done at $width px', (tester) async {
      await _pump(tester, width);
      await _search(tester);
      await _step(tester, line: 'Portland', times: 10);
      await _step(tester, line: 'Marine', times: 2);
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason for the return (required)'),
        'Two bags split in transit, plywood corners chipped.',
      );
      await tester.pumpAndSettle();
      await _confirm(tester, width);
      await _capture('c7-done-$width.png');
    }, skip: !enabled);
  }

  testWidgets('error at 760 px', (tester) async {
    await _pump(tester, 760, failPostNoShift: true);
    await _search(tester);
    await _step(tester, line: 'Portland', times: 2);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for the return (required)'),
      'Two bags split in transit.',
    );
    await tester.pumpAndSettle();
    await _confirm(tester, 760);
    expect(
      find.byType(ErrorBanner),
      findsOneWidget,
      reason:
          'the refusal must be the first thing on the page, not under the '
          'pinned bar where the cashier tapped Confirm',
    );
    await _capture('c7-error-760.png');
  }, skip: !enabled);
}

Future<void> _capture(String name) async {
  await expectLater(
    find.byKey(_rootKey),
    matchesGoldenFile(Uri.file('$_goldenDir/$name')),
  );
}

/// Confirm lives in the pinned bar at a narrow width and in the Refund step on a
/// wide one, so the two never both appear: tap whichever is on screen.
Future<void> _confirm(WidgetTester tester, int width) async {
  final button = find.widgetWithText(FilledButton, 'Confirm return');
  // A wide window keeps Confirm at the bottom of the Refund step, which may sit
  // below the fold once the reason's counter is drawn.
  await tester.ensureVisible(button.last);
  await tester.pumpAndSettle();
  await tester.tap(button.last);
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Post return'));
  await tester.pumpAndSettle();
}

/// Narrow windows stack the steps; scroll the lines into view so the picture
/// shows the step being reviewed rather than only step 1.
Future<void> _revealChoices(WidgetTester tester, int width) async {
  if (width > 900) return;
  await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -340));
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  int width, {
  bool failPostNoShift = false,
}) async {
  tester.view.physicalSize = Size(width.toDouble(), 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final returnsViewmodel = PosReturnsViewmodel(
    repository: _GoldenReturns(failPostNoShift: failPostNoShift),
  );
  final shiftViewmodel = ShiftViewmodel(service: _GoldenShifts());

  final router = GoRouter(
    initialLocation: AppRoutes.posReturns,
    routes: [
      GoRoute(
        path: AppRoutes.posReturns,
        builder: (context, state) => PosReturnsPage(
          viewmodel: returnsViewmodel,
          shiftViewmodel: shiftViewmodel,
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    RepaintBoundary(
      key: _rootKey,
      child: ChangeNotifierProvider<AuthViewmodel>.value(
        value: _cashier(),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          // The real theme, so the shot uses the brand faces and sizes. Without
          // it every slot renders in the test harness's box font.
          theme: AppTheme.lightTheme.copyWith(
            textTheme: AppTheme.lightTheme.textTheme.apply(
              fontFamilyFallback: const ['PesoFallback'],
            ),
          ),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _search(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'OR-20261024-0012');
  await tester.tap(find.widgetWithText(FilledButton, 'Search sale'));
  await tester.pumpAndSettle();
}

/// Steps ONE named line, found by its row text, so the counts are exact.
Future<void> _step(
  WidgetTester tester, {
  required String line,
  required int times,
}) async {
  final row = find.ancestor(
    of: find.textContaining(line),
    matching: find.byType(Row),
  );
  final plus = find.descendant(
    of: row.first,
    matching: find.byTooltip('One more'),
  );
  for (var i = 0; i < times; i++) {
    await tester.tap(plus.first);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

AuthViewmodel _cashier() =>
    AuthViewmodel(AuthRepository(AuthService()))
      ..user = const User(
        id: 7,
        username: 'cashier',
        email: 'cashier@buildpro.ph',
        fullName: 'Ana Cruz',
        role: Role(id: 3, name: 'pos', displayName: 'Cashier'),
        isActive: true,
      );

class _GoldenShifts extends ShiftService {
  @override
  Future<Shift?> fetchCurrent() async => Shift(
    id: 4,
    cashierName: 'Ana Cruz',
    status: Shift.openStatus,
    openingFloat: 5000,
    closingCount: null,
    openedAt: DateTime(2026, 10, 24, 8),
    closedAt: null,
    notes: '',
    zReading: null,
  );

  @override
  Future<List<Shift>> fetchAll() async => const [];
}

class _GoldenReturns extends ReturnsRepository {
  _GoldenReturns({this.failPostNoShift = false});

  final bool failPostNoShift;

  @override
  Future<TransactionRecord?> findSale(String query) async => TransactionRecord(
    id: 18,
    transactionNo: 'TRX-20261024-0012',
    transDate: DateTime(2026, 10, 24, 9),
    customerId: 2,
    // Long on purpose: the header must wrap, never clip.
    customerName: 'Northern Luzon Builders and Construction Supply Corporation',
    cashierName: 'Ana Cruz',
    source: 'CHARGE',
    originalTransactionId: null,
    status: 'COMPLETED',
    // Seven digits on purpose: money must not ellipsize.
    grandTotal: 1234567.89,
    items: const [],
    payments: const [],
  );

  @override
  Future<ReturnableSale> fetchReturnable(int transactionId) async =>
      const ReturnableSale(
        transactionNo: 'TRX-20261024-0012',
        customer: 'Northern Luzon Builders and Construction Supply Corporation',
        source: 'CHARGE',
        returnable: true,
        reasonIfNot: null,
        openDebt: 5000,
        lines: [
          ReturnableLine(
            variantUomId: 8,
            name: 'Portland Cement Type 1 40 kg (50 kg bag)',
            uom: 'BAG',
            soldQty: 40,
            returnedQty: 2,
            remainingQty: 38,
            unitPrice: 285,
          ),
          ReturnableLine(
            variantUomId: 9,
            name: 'Deformed Steel Bar 10 mm x 6 m',
            uom: 'PC',
            soldQty: 25,
            returnedQty: 25,
            remainingQty: 0,
            unitPrice: 250,
          ),
          ReturnableLine(
            variantUomId: 10,
            name: 'Marine Plywood 3/4 in x 4 x 8 ft',
            uom: 'SHEET',
            soldQty: 12,
            returnedQty: 0,
            remainingQty: 12,
            unitPrice: 1480.5,
          ),
        ],
      );

  @override
  Future<ReturnResult> postReturn({
    required int customerId,
    required int originalTransactionId,
    required String reason,
    required String paymentMethod,
    required List<ReturnRequestLine> lines,
  }) async {
    if (failPostNoShift) {
      throw const ReturnsServiceException(
        'You have no open shift. Open a shift before posting a return.',
        code: 'NO_OPEN_SHIFT',
        needsOpenShift: true,
      );
    }
    return const ReturnResult(
      returnNo: 'RTN-20261024-0003',
      refund: RefundSummary(
        returnValue: 5811,
        debtReduced: 5000,
        cashRefund: 811,
        refundMethod: 'CASH',
        ledgerId: 5,
        ledgerBalance: 0,
      ),
    );
  }
}

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
