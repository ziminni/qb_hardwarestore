@Tags(['golden'])
library;

// Phase 1b Task 7: the "Requests from projects" screen and its review dialog,
// painted with the real fonts into the SDD folder (gitignored masters).
//
// ```
// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
//   test/features/requisitions/project_requests_golden_test.dart
// ```
//
// Why these four: the queue at the wide and narrow window, the badge on the
// sidebar, the review dialog with one Not-available line and its reason, and a
// read-only accepted request whose expected amount is unknown (decision 14).
import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/requisitions/viewmodels/project_requests_viewmodel.dart';
import 'package:client/features/requisitions/views/project_requests_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

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
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  for (final entry in const [
    ('1440', Size(1440, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('requests from projects at ${entry.$1} px', (tester) async {
      await _pump(tester, entry.$2, _queueRepository());
      await _expectLater(tester, goldenDir, 'p1-requests-${entry.$1}.png');
    }, skip: !enabled);
  }

  testWidgets('the review dialog at 760 px', (tester) async {
    await _pump(tester, const Size(760, 900), _queueRepository());
    await tester.tap(find.text('Review').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('line-101-available')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('line-102-not-available')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('line-102-reason')),
      'Not stocked: 16 mm bars ran out last week.',
    );
    await tester.pumpAndSettle();
    await _expectLater(tester, goldenDir, 'p1-review-dialog-760.png');
  }, skip: !enabled);

  testWidgets('a read-only accepted request in the admin shell at 1100 px', (
    tester,
  ) async {
    await _pump(
      tester,
      const Size(1100, 900),
      _queueRepository(),
      adminShell: true,
      status: RequisitionStatus.accepted,
    );
    await tester.tap(find.text('View').first);
    await tester.pumpAndSettle();
    await _expectLater(tester, goldenDir, 'p1-read-only-1100.png');
  }, skip: !enabled);
}

const _goldenKey = ValueKey('P1RequestsGolden');

RequisitionItem _line({
  required int id,
  required String productName,
  required String variantName,
  required String unit,
  required double quantity,
  bool? available,
  String declineReason = '',
}) => RequisitionItem(
  id: id,
  variantId: id,
  variantName: variantName,
  quantity: quantity,
  releasedQty: 0,
  productName: productName,
  unit: unit,
  available: available,
  declineReason: declineReason,
);

Requisition _request({
  required int id,
  required String reqNumber,
  required String status,
  required String project,
  required String customer,
  required String requestedBy,
  String? approver,
  String notes = '',
  String declineReason = '',
  double? expectedAmount,
  required List<RequisitionItem> items,
}) => Requisition(
  id: id,
  reqNumber: reqNumber,
  rawStatus: status,
  projectName: project,
  projectCustomerName: customer,
  requestedByName: requestedBy,
  items: items,
  cpmsRequestId: 'CPMS-REQ-884$id',
  // Oldest first, on real November days: the queue reads by received date.
  createdAt: DateTime(2026, 11, 2 + (id % 5)),
  approverName: approver,
  notes: notes,
  declineReason: declineReason,
  expectedAmount: expectedAmount,
);

class _StubRepository extends RequisitionRepository {
  _StubRepository(this.rows);
  final List<Requisition> rows;

  @override
  Future<List<Requisition>> fetchRequisitions({String? status}) async => [
    for (final row in rows)
      if (status == null || row.rawStatus == status) row,
  ];

  @override
  Future<int> waitingCount() async =>
      rows.where((row) => row.status == RequisitionStatus.waiting).length;

  @override
  Future<Requisition> fetchRequisition(int id) async =>
      rows.firstWhere((row) => row.id == id);
}

_StubRepository _queueRepository() => _StubRepository([
  _request(
    id: 101,
    reqNumber: 'REQ-20261107-0007',
    status: 'WAITING',
    project: 'Dela Cruz Construction Warehouse Extension Phase 2',
    customer: 'Dela Cruz Construction',
    requestedBy: 'Ben Cruz',
    approver: 'Engr. Reyes',
    notes: 'Deliver to gate 2 before noon. Gate 1 is closed to trucks.',
    items: [
      _line(
        id: 101,
        productName: 'Portland Cement',
        variantName: '40 kg',
        unit: '40 kg bag',
        quantity: 120,
      ),
      _line(
        id: 102,
        productName: 'Steel bar 16 mm x 6 m',
        variantName: 'Grade 60',
        unit: 'length',
        quantity: 24,
      ),
    ],
  ),
  _request(
    id: 102,
    reqNumber: 'REQ-20261107-0008',
    status: 'WAITING',
    project: 'Coastal Road Retaining Wall Section 3',
    customer: 'Mactan Builders Inc.',
    requestedBy: 'Ana Lopez',
    approver: 'Engr. Santos',
    items: [
      _line(
        id: 103,
        productName: 'Marine Plywood',
        variantName: '3/4 in',
        unit: 'sheet',
        quantity: 36,
      ),
    ],
  ),
  _request(
    id: 103,
    reqNumber: 'REQ-20261105-0004',
    status: 'ACCEPTED',
    project: 'Barangay Hall Roof Replacement',
    customer: 'Lapu-Lapu LGU',
    requestedBy: 'Ben Cruz',
    approver: 'Engr. Reyes',
    expectedAmount: null,
    items: [
      _line(
        id: 104,
        productName: 'Pre-painted Rib Type Roofing',
        variantName: '0.40 mm x 8 ft',
        unit: 'sheet',
        quantity: 48,
        available: true,
      ),
      _line(
        id: 105,
        productName: 'C-purlins 2 x 3',
        variantName: '1.2 mm',
        unit: 'length',
        quantity: 20,
        available: false,
        declineReason: 'Not stocked in this length.',
      ),
    ],
  ),
]);

Future<void> _pump(
  WidgetTester tester,
  Size size,
  RequisitionRepository repository, {
  bool adminShell = false,
  RequisitionStatus status = RequisitionStatus.waiting,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final viewmodel = ProjectRequestsViewmodel(repository: repository);
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth.user = User(
    id: 1,
    username: adminShell ? 'admin' : 'manager',
    email: 'user@qb.local',
    fullName: adminShell ? 'Rosario Dela Cruz Mendoza' : 'Maria Santos',
    role: Role(
      id: 1,
      name: adminShell ? 'admin' : 'sales',
      displayName: adminShell ? 'Admin' : 'Store Manager',
    ),
  );

  await tester.pumpWidget(
    RepaintBoundary(
      key: _goldenKey,
      child: ChangeNotifierProvider<AuthViewmodel>.value(
        value: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: adminShell
              ? AdminProjectRequestsPage(viewmodel: viewmodel)
              : ProjectRequestsPage(viewmodel: viewmodel),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (status != RequisitionStatus.waiting) {
    await tester.tap(
      find.text(
        RequisitionStatus.accepted == status ? 'Accepted' : status.label,
      ),
    );
    await tester.pumpAndSettle();
  }

  // Decode the images actually on screen; guessed logo sizes missed the
  // collapsed rail's, which then painted late under parallel load.
  await tester.runAsync(() async {
    for (final element in tester.elementList(find.byType(Image))) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: 'a layout overflow would paint yellow stripes into the PNG',
  );
}

Future<void> _expectLater(
  WidgetTester tester,
  Directory goldenDir,
  String name,
) => expectLater(
  find.byKey(_goldenKey),
  matchesGoldenFile(Uri.file('${goldenDir.path}/$name')),
);

ThemeData _theme() => AppTheme.lightTheme.copyWith(
  textTheme: AppTheme.lightTheme.textTheme.apply(
    fontFamilyFallback: const [_pesoFallbackFamily],
  ),
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
