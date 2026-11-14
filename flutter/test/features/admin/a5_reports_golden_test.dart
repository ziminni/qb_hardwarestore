@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/admin/viewmodels/admin_reports_viewmodel.dart';
import 'package:client/features/admin/views/reports_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/views/sales_reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The fallback visual check (00-shared/VERIFY.md, fallback 3) for card A5: the
/// real Reports screen in BOTH shells it is shown in (admin and Store Manager),
/// painted with the real fonts and written as PNGs into the SDD folder.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/admin/a5_reports_golden_test.dart
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
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
    // The bundled brand fonts stop at Latin, so every peso sign would be a box.
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
    testWidgets('Sales report in the admin shell at ${entry.$1} px', (
      tester,
    ) async {
      await _pump(
        tester,
        entry.$2,
        ReportsPage(viewmodel: _viewmodel()),
        auth: _adminAuth(),
      );
      await _expectLater(tester, goldenDir, 'a5-sales-${entry.$1}.png');
    }, skip: !enabled);
  }

  testWidgets('Movements report at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      ReportsPage(viewmodel: _viewmodel()),
      auth: _adminAuth(),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(TabBar),
        matching: find.text('Movements'),
      ),
    );
    await tester.pumpAndSettle();
    await _expectLater(tester, goldenDir, 'a5-movements-760.png');
  }, skip: !enabled);

  testWidgets('Valuation report at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      ReportsPage(viewmodel: _viewmodel()),
      auth: _adminAuth(),
    );
    await _openTab(tester, 'Valuation');
    await _expectLater(tester, goldenDir, 'a5-valuation-760.png');
  }, skip: !enabled);

  // The widest table (five columns, one of them a status badge) and the longest
  // project name: at 1100 nothing in it may ellipsize or wrap.
  testWidgets('Requisitions report at 1100 px', (tester) async {
    await _pump(
      tester,
      const Size(1100, 900),
      ReportsPage(viewmodel: _viewmodel()),
      auth: _adminAuth(),
    );
    await _openTab(tester, 'Requisitions');
    await _expectLater(tester, goldenDir, 'a5-requisitions-1100.png');
  }, skip: !enabled);

  testWidgets('a failed first load at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      ReportsPage(viewmodel: _viewmodel(failSales: true)),
      auth: _adminAuth(),
    );
    expect(find.text('The sales summary could not be loaded.'), findsOneWidget);
    await _expectLater(tester, goldenDir, 'a5-error-760.png');
  }, skip: !enabled);

  testWidgets('an empty period at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      ReportsPage(viewmodel: _viewmodel(emptySales: true)),
      auth: _adminAuth(),
    );
    expect(find.text('No sales in this range.'), findsOneWidget);
    await _expectLater(tester, goldenDir, 'a5-empty-760.png');
  }, skip: !enabled);

  testWidgets('the same content in the Store Manager shell at 1100 px', (
    tester,
  ) async {
    await _pump(
      tester,
      const Size(1100, 900),
      SalesReportsPage(viewmodel: _viewmodel()),
      auth: _managerAuth(),
    );
    await _expectLater(tester, goldenDir, 'a5-store-manager-1100.png');
  }, skip: !enabled);

  testWidgets('the date range picker open at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      ReportsPage(viewmodel: _viewmodel()),
      auth: _adminAuth(),
    );
    await tester.tap(find.byKey(const Key('reports-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom range'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await _expectLater(tester, goldenDir, 'a5-date-picker-760.png');
  }, skip: !enabled);
}

const _goldenKey = ValueKey('A5ReportsGolden');

/// The tab is named in the TabBar and may also be a row word; the tab is the one
/// inside the bar.
Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(TabBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Stands in for the platform font the app itself falls back to for a glyph the
/// brand fonts do not have.
const String _pesoFallbackFamily = 'PesoFallback';

const List<String> _pesoFontCandidates = [
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  '/usr/share/fonts/TTF/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  'C:/Windows/Fonts/arial.ttf',
];

/// The reports a working week produces: five trading days, four stock
/// categories and a requisition history. The gross total is ₱1,284,930.00,
/// seven digits, so the money tiles have to group thousands.
class _StubReportsRepository extends ReportsRepository {
  _StubReportsRepository({this.failSales = false, this.emptySales = false});

  final bool failSales;
  final bool emptySales;

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    if (failSales) {
      throw const ReportsServiceException(
        'The sales summary could not be loaded.',
      );
    }
    if (emptySales) {
      return const SalesSummary(
        from: '2026-10-01',
        to: '2026-10-31',
        totalTransactions: 0,
        totalGross: 0,
        totalVat: 0,
        totalDiscounts: 0,
        days: [],
      );
    }
    return const SalesSummary(
      from: '2026-10-01',
      to: '2026-10-31',
      totalTransactions: 137,
      totalGross: 1284930,
      totalVat: 0,
      totalDiscounts: 0,
      days: [
        SalesDay(
          day: '2026-10-26',
          transactions: 31,
          gross: 241860,
          vat: 0,
          discounts: 0,
        ),
        SalesDay(
          day: '2026-10-27',
          transactions: 28,
          gross: 198420,
          vat: 0,
          discounts: 0,
        ),
        SalesDay(
          day: '2026-10-28',
          transactions: 33,
          gross: 312750,
          vat: 0,
          discounts: 0,
        ),
        SalesDay(
          day: '2026-10-29',
          transactions: 26,
          gross: 388900,
          vat: 0,
          discounts: 0,
        ),
        SalesDay(
          day: '2026-10-30',
          transactions: 19,
          gross: 143000,
          vat: 0,
          discounts: 0,
        ),
      ],
    );
  }

  @override
  Future<InventoryValuation> fetchInventoryValuation() async {
    return const InventoryValuation(
      batchCount: 75,
      totalUnits: 13414,
      totalCost: 4498000,
      totalRetail: 5649000,
      categories: [
        ValuationCategory(
          id: 1,
          name: 'Cement and Aggregates',
          batchCount: 42,
          units: 12480,
          cost: 3120000,
          retail: 3900000,
        ),
        ValuationCategory(
          id: 2,
          name: 'Steel bars and Structural',
          batchCount: 18,
          units: 640,
          cost: 1240000,
          retail: 1560000,
        ),
        ValuationCategory(
          id: 3,
          name: 'Plywood and Boards',
          batchCount: 6,
          units: 210,
          cost: 96000,
          retail: 128000,
        ),
        ValuationCategory(
          id: 4,
          name: 'Paint and Finishes',
          batchCount: 9,
          units: 84,
          cost: 42000,
          retail: 61000,
        ),
      ],
    );
  }

  @override
  Future<StockMovements> fetchStockMovements({String? from, String? to}) async {
    return const StockMovements(
      from: '2026-10-01',
      to: '2026-10-31',
      totalIn: 950,
      totalOut: 64,
      receiptsByDay: [
        MovementDay(date: '2026-10-26', receipts: 2, qtyIn: 320),
        MovementDay(date: '2026-10-28', receipts: 1, qtyIn: 150),
        MovementDay(date: '2026-10-30', receipts: 3, qtyIn: 480),
      ],
      adjustmentsByType: [
        MovementType(type: 'DAMAGE', movements: 4, qtyOut: 18),
        MovementType(type: 'SHRINKAGE', movements: 2, qtyOut: 6),
        MovementType(type: 'RETURN', movements: 1, qtyOut: 40),
      ],
    );
  }

  @override
  Future<RequisitionHistory> fetchRequisitionHistory() async {
    return const RequisitionHistory(
      from: '2026-10-01',
      to: '2026-10-31',
      statusFilter: null,
      countByStatus: {
        'SUBMITTED': 3,
        'ACCEPTED': 5,
        'PARTIAL': 2,
        'RELEASED': 12,
        'CLOSED': 4,
        'REJECTED': 1,
      },
      requisitions: [
        RequisitionHistoryRow(
          id: 41,
          reqNumber: 'REQ-20261030-0007',
          status: 'SUBMITTED',
          project: 'Dela Cruz Construction Warehouse Extension Phase 2',
          requestedBy: 'Ben Cruz',
          approvedBy: null,
          createdAt: '2026-10-30T15:42:00Z',
        ),
        RequisitionHistoryRow(
          id: 40,
          reqNumber: 'REQ-20261029-0006',
          status: 'ACCEPTED',
          project: 'Marine Plywood Formwork Repairs',
          requestedBy: 'Ana Lopez',
          approvedBy: 'Maria Santos',
          createdAt: '2026-10-29T11:12:00Z',
        ),
        RequisitionHistoryRow(
          id: 39,
          reqNumber: 'REQ-20261028-0005',
          status: 'RELEASED',
          project: 'Site 2 Slab Pour',
          requestedBy: 'Ben Cruz',
          approvedBy: 'Maria Santos',
          createdAt: '2026-10-28T08:05:00Z',
        ),
        // Task 10: the two statuses CPMS and the till write today.
        RequisitionHistoryRow(
          id: 38,
          reqNumber: 'REQ-20261027-0004',
          status: 'PARTIAL',
          project: 'Coastal Road Retaining Wall Section 3',
          requestedBy: 'Ana Lopez',
          approvedBy: 'Maria Santos',
          createdAt: '2026-10-27T14:20:00Z',
        ),
        RequisitionHistoryRow(
          id: 37,
          reqNumber: 'REQ-20261026-0003',
          status: 'CLOSED',
          project: 'Barangay Hall Roof Replacement',
          requestedBy: 'Ben Cruz',
          approvedBy: 'Ana Lopez',
          createdAt: '2026-10-26T09:15:00Z',
        ),
      ],
    );
  }
}

AdminReportsViewmodel _viewmodel({
  bool failSales = false,
  bool emptySales = false,
}) => AdminReportsViewmodel(
  repository: _StubReportsRepository(
    failSales: failSales,
    emptySales: emptySales,
  ),
);

Future<void> _pump(
  WidgetTester tester,
  Size size,
  Widget page, {
  required AuthViewmodel auth,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _goldenKey,
      child: ChangeNotifierProvider<AuthViewmodel>.value(
        value: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: page,
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

Future<void> _expectLater(
  WidgetTester tester,
  Directory goldenDir,
  String name,
) => expectLater(
  find.byKey(_goldenKey),
  matchesGoldenFile(Uri.file('${goldenDir.path}/$name')),
);

ThemeData _theme() => AppTheme.lightTheme.copyWith(
  // Only the goldens: lets a peso sign fall back to the system font the app
  // itself uses, because the brand fonts stop at Latin.
  textTheme: AppTheme.lightTheme.textTheme.apply(
    fontFamilyFallback: const [_pesoFallbackFamily],
  ),
);

AuthViewmodel _adminAuth() => _auth(
  fullName: 'Rosario Dela Cruz Mendoza',
  role: 'admin',
  roleLabel: 'Admin',
  username: 'admin',
);

AuthViewmodel _managerAuth() => _auth(
  fullName: 'Maria Santos',
  role: 'manager',
  roleLabel: 'Store Manager',
  username: 'manager',
);

AuthViewmodel _auth({
  required String fullName,
  required String role,
  required String roleLabel,
  required String username,
}) {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth.user = User(
    id: 1,
    username: username,
    email: '$username@qb.local',
    fullName: fullName,
    role: Role(id: 1, name: role, displayName: roleLabel),
  );
  return auth;
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
