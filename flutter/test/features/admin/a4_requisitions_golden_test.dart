@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/admin/viewmodels/admin_requisitions_viewmodel.dart';
import 'package:client/features/admin/views/requisitions_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The fallback visual check (00-shared/VERIFY.md, fallback 3) for card A4: the
/// requisition queue in both shells, its empty and error states, one row's
/// detail (where the release token lives) and the approval's confirmation,
/// rendered with the REAL fonts and the REAL theme into the SDD folder.
///
/// Same opt-in mechanism as F3's gallery, so the normal suite never fails on a
/// font or platform difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/admin/a4_requisitions_golden_test.dart
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
    // The release token is a monospace credential, and the harness has no
    // system fonts: without this the token renders as empty boxes.
    for (final mono in const [
      '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf',
      '/usr/share/fonts/dejavu/DejaVuSansMono.ttf',
    ]) {
      if (File(mono).existsSync()) {
        await _loadFontFile('monospace', mono);
        break;
      }
    }
  });

  for (final entry in const [
    ('1440', Size(1440, 900)),
    ('1100', Size(1100, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('requisition queue at ${entry.$1} px', (tester) async {
      await _pump(tester, entry.$2, _queuePage(_stub([..._queue])));
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/a4-queue-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('requisition queue empty at 760 px', (tester) async {
    await _pump(tester, const Size(760, 900), _queuePage(_stub(const [])));
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/a4-empty-760.png')),
    );
  }, skip: !enabled);

  testWidgets('requisition queue failed load at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      _queuePage(
        _stub(const [], failure: 'The requisitions could not be loaded.'),
      ),
    );
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/a4-error-760.png')),
    );
  }, skip: !enabled);

  testWidgets('requisition queue in the Store Manager shell at 1100 px', (
    tester,
  ) async {
    await _pump(
      tester,
      const Size(1100, 900),
      _queuePage(_stub([..._queue]), inSalesShell: true),
    );
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/a4-store-manager-1100.png'),
      ),
    );
  }, skip: !enabled);

  testWidgets('one approved requisition with its token at 1100 px', (
    tester,
  ) async {
    await _pump(tester, const Size(1100, 900), _queuePage(_stub([..._queue])));
    // The detail is where the token lives; SHOWN here so the golden proves the
    // credential, the Copy button and the panel layout together.
    await tester.tap(find.text('REQ-20261029-0007'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/a4-detail-1100.png')),
    );
  }, skip: !enabled);

  testWidgets('a released requisition says its token is Used at 1100 px', (
    tester,
  ) async {
    await _pump(tester, const Size(1100, 900), _queuePage(_stub([..._queue])));
    // D17: the token stays, labelled Used, because it is the record of how the
    // goods went out and can release nothing again.
    await tester.tap(find.text('REQ-20261028-0011'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/a4-detail-used-1100.png')),
    );
  }, skip: !enabled);

  testWidgets('the approval confirmation at 1100 px', (tester) async {
    await _pump(tester, const Size(1100, 900), _queuePage(_stub([..._queue])));
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/a4-approve-dialog-1100.png'),
      ),
    );
  }, skip: !enabled);
}

const _goldenKey = ValueKey('RequisitionsGolden');

Widget _queuePage(
  RequisitionRepository repository, {
  bool inSalesShell = false,
}) {
  return RequisitionsPage(
    viewmodel: AdminRequisitionsViewmodel(repository: repository),
    inSalesShell: inSalesShell,
  );
}

/// Answers from memory; no PNG depends on a server.
class _StubRequisitions extends RequisitionRepository {
  _StubRequisitions(this.rows, {this.failure});

  final List<Requisition> rows;
  final String? failure;

  @override
  Future<List<Requisition>> fetchRequisitions() async {
    final failure = this.failure;
    if (failure != null) throw RequisitionServiceException(failure);
    return rows;
  }

  @override
  Future<String> approve(int requisitionId) async =>
      '8c1f0b7e-4a2d-4b6f-9d31-2a7f0000${requisitionId.toString().padLeft(4, '0')}';

  @override
  Future<void> reject(int requisitionId) async {}
}

RequisitionRepository _stub(List<Requisition> rows, {String? failure}) =>
    _StubRequisitions(rows, failure: failure);

RequisitionItem _item(
  int id,
  String name,
  double quantity, {
  double released = 0,
}) => RequisitionItem(
  id: id,
  variantId: id,
  variantName: name,
  quantity: quantity,
  releasedQty: released,
);

/// A morning's queue: two waiting, one approved with a token, one released,
/// one rejected. One project name and one item name are long on purpose, and
/// one quantity is five digits, so a squeezed table shows in the PNG.
final List<Requisition> _queue = [
  Requisition(
    id: 1,
    reqNumber: 'REQ-20261030-0001',
    rawStatus: 'SUBMITTED',
    projectName: '3-Storey Residential Building - Banilad, Cebu City',
    projectCustomerName: 'Dela Cruz Construction and Development Corporation',
    requestedByName: 'Ramonito Villanueva',
    items: [
      _item(1, 'Portland Cement 40 kg', 1250),
      _item(2, 'Deformed Steel Bar 10 mm x 6 m', 180),
      _item(3, 'Marine Plywood 3/4 in', 24),
    ],
  ),
  Requisition(
    id: 2,
    reqNumber: 'REQ-20261030-0002',
    rawStatus: 'SUBMITTED',
    projectName: '2-Storey House - Mandaue',
    projectCustomerName: 'Dela Cruz Construction',
    requestedByName: 'Fore Man',
    items: [
      _item(4, 'PVC Pipe 2 in x 3 m', 12),
      _item(5, 'Latex Paint White 4 L', 6),
    ],
  ),
  Requisition(
    id: 3,
    reqNumber: 'REQ-20261029-0007',
    rawStatus: 'APPROVED',
    projectName: 'Warehouse Extension - Consolacion',
    projectCustomerName: 'Northline Trading',
    requestedByName: 'Editha Ramos',
    items: [_item(6, 'Coco Lumber 2 x 3 x 10 ft', 60)],
    token: '8c1f0b7e-4a2d-4b6f-9d31-2a7f00000003',
  ),
  Requisition(
    id: 4,
    reqNumber: 'REQ-20261028-0011',
    rawStatus: 'RELEASED',
    projectName: '2-Storey House - Mandaue',
    projectCustomerName: 'Dela Cruz Construction',
    requestedByName: 'Fore Man',
    items: [
      _item(7, 'Portland Cement 40 kg', 40, released: 40),
      _item(8, 'Hollow Blocks 4 in', 500, released: 500),
    ],
    token: '8c1f0b7e-4a2d-4b6f-9d31-2a7f00000004',
  ),
  Requisition(
    id: 5,
    reqNumber: 'REQ-20261027-0003',
    rawStatus: 'REJECTED',
    projectName: 'Fence Repair - Talisay',
    projectCustomerName: 'San Isidro Parish',
    requestedByName: 'Ramonito Villanueva',
    items: [_item(9, 'Common Nails 3 in', 20)],
  ),
];

Future<void> _pump(WidgetTester tester, Size size, Widget page) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      // The boundary wraps the MaterialApp, not its `home`: a dialog is a route
      // in the app's own Navigator, so a boundary inside `home` would crop the
      // dialog and its scrim straight out of the PNG.
      child: RepaintBoundary(
        key: _goldenKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: ColoredBox(
            color: AppTheme.lightTheme.colorScheme.surface,
            child: page,
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
