@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:client/features/pos/views/material_release_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The fallback visual check for C3 (00-shared/VERIFY.md, fallback 3): the real
/// Release materials page, inside the real Cashier shell, painted with the real
/// fonts and written as PNGs into the SDD folder so the layout can be looked at
/// without a browser.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/pos/material_release_page_golden_test.dart
/// ```
void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

  // Absolute: the PNGs belong to the MAIN checkout's SDD folder, not to this
  // card's worktree.
  final goldenDir = Directory(
    '/home/yaji/projects/qb_ecosystem/qb_pos_inventory_system'
    '/.superpowers/sdd/ui-refresh/goldens',
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
    // The test harness does not load the Material icon font, so every Icon
    // would be a box in the PNG.
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) {
      await _loadFontFile('MaterialIcons', icons);
    }
    // The bundled brand fonts stop at Latin, so every peso sign needs a system
    // font that carries it.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  for (final width in const [
    ('1440', Size(1440, 900)),
    ('1100', Size(1100, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('empty at ${width.$1} px', (tester) async {
      await _pumpRelease(tester, width.$2, _StubRequisitions());

      expect(find.text('Verify the token'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Release materials'),
        findsNothing,
      );

      await _expectPng(tester, goldenDir, 'c3-empty-${width.$1}.png');
    }, skip: !enabled);

    testWidgets('verified at ${width.$1} px', (tester) async {
      await _pumpRelease(tester, width.$2, _StubRequisitions());
      await _verify(tester);

      expect(find.text('REQ-20261024-0117'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Release materials'),
        findsOneWidget,
      );

      await _expectPng(tester, goldenDir, 'c3-verified-${width.$1}.png');
    }, skip: !enabled);

    testWidgets('released at ${width.$1} px', (tester) async {
      await _pumpRelease(tester, width.$2, _StubRequisitions());
      await _verify(tester);
      await _release(tester);

      expect(find.textContaining('TXN-20261030-0184'), findsWidgets);
      expect(find.textContaining('1,234,567.89'), findsWidgets);
      expect(
        find.widgetWithText(OutlinedButton, 'Verify another token'),
        findsOneWidget,
      );

      await _expectPng(tester, goldenDir, 'c3-released-${width.$1}.png');
    }, skip: !enabled);

    testWidgets('no open shift at ${width.$1} px', (tester) async {
      await _pumpRelease(
        tester,
        width.$2,
        _StubRequisitions()
          ..failRelease = const RequisitionServiceException(
            'You have no open shift. Open a shift before releasing materials.',
            code: 'NO_OPEN_SHIFT',
          ),
      );
      await _verify(tester);
      await _release(tester);

      expect(
        find.textContaining('Open a shift before releasing'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Go to Shifts'),
        findsOneWidget,
      );

      await _expectPng(tester, goldenDir, 'c3-no-shift-${width.$1}.png');
    }, skip: !enabled);
  }
}

const pageKey = ValueKey('MaterialReleasePageGolden');

/// One action and one shot: a printed token, a long project and customer, and
/// a line whose name runs past a narrow column.
class _StubRequisitions extends RequisitionRepository {
  Object? failRelease;

  @override
  Future<TokenVerification> verifyToken(String token) async =>
      TokenVerification(
        token: token,
        requisitionId: 17,
        reqNumber: 'REQ-20261024-0117',
        project: '2-Storey Residential House - Mandaue City',
        customer: 'Dela Cruz Construction and Supply Corporation',
        items: const [
          VerifiedRequisitionItem(
            id: 1,
            variantId: 7,
            variantName: 'Portland Cement 40 kg',
            quantity: 120,
            remaining: 120,
          ),
          VerifiedRequisitionItem(
            id: 2,
            variantId: 9,
            variantName: 'Deformed Steel Bar 10 mm x 6 m Grade 60',
            quantity: 48,
            remaining: 48,
          ),
          VerifiedRequisitionItem(
            id: 3,
            variantId: 12,
            variantName: 'Marine Plywood 3/4 in',
            quantity: 24,
            remaining: 12,
          ),
          VerifiedRequisitionItem(
            id: 4,
            variantId: 15,
            variantName: 'PVC Pipe 2 in x 3 m',
            quantity: 6,
            remaining: 6,
          ),
        ],
      );

  @override
  Future<ReleaseResult> release(String token) async {
    if (failRelease case final failure?) throw failure;
    return const ReleaseResult(
      transactionId: 184,
      transactionNo: 'TXN-20261030-0184',
      grandTotal: 1234567.89,
      ledgerId: 41,
      balanceDue: 1234567.89,
    );
  }
}

Future<void> _verify(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'b1e0c4d2-token-0117');
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
  await tester.pumpAndSettle();
}

Future<void> _release(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Release materials');
  // At 760 px the action sits below the fold of the shell's scroll view.
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  // The shot starts where the clerk starts: on the token, not on whatever
  // happened to be scrolled into view.
  await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 2000));
  await tester.pumpAndSettle();
}

Future<void> _expectPng(WidgetTester tester, Directory dir, String name) async {
  await expectLater(
    find.byKey(pageKey),
    matchesGoldenFile(Uri.file('${dir.path}/$name')),
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

Future<void> _pumpRelease(
  WidgetTester tester,
  Size size,
  RequisitionRepository repository,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final viewmodel = MaterialReleaseViewmodel(repository: repository);
  addTearDown(viewmodel.dispose);

  await tester.pumpWidget(
    RepaintBoundary(
      key: pageKey,
      child: ChangeNotifierProvider<AuthViewmodel>.value(
        value: AuthViewmodel(AuthRepository(AuthService())),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme.copyWith(
            // Only the goldens: lets a peso sign fall back to the system font
            // the app itself uses, because the brand fonts stop at Latin.
            textTheme: AppTheme.lightTheme.textTheme.apply(
              fontFamilyFallback: const [_pesoFallbackFamily],
            ),
          ),
          home: MaterialReleasePage(viewmodel: viewmodel),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
