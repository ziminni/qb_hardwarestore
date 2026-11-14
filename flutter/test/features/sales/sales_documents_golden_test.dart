@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/views/sales_orders_page.dart';
import 'package:client/features/sales/views/sales_quotations_page.dart';
import 'package:client/features/sales/widgets/sales_document_list_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The visual check for card M3 (00-shared/VERIFY.md, fallback 3): both
/// document screens, with the REAL fonts and the REAL theme, written as PNGs
/// into the SDD folder so the layout can be looked at without a browser.
///
/// Same opt-in mechanism as the shared components' golden test, so the normal
/// suite never fails on a font or platform difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/sales/sales_documents_golden_test.dart
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
              '${goldenDir.path}/m3-${screen.name}-list-${entry.$1}.png',
            ),
          ),
        );
      }, skip: !enabled);
    }

    testWidgets('${screen.name} empty at 760 px', (tester) async {
      await _pump(tester, screen, const Size(760, 900), empty: true);
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/m3-${screen.name}-empty-760.png'),
        ),
      );
    }, skip: !enabled);

    testWidgets('${screen.name} error at 760 px', (tester) async {
      await _pump(
        tester,
        screen,
        const Size(760, 900),
        failure: switch (screen.kind) {
          SalesDocumentKind.quotation =>
            'The quotation list did not finish loading. Try again.',
          SalesDocumentKind.order =>
            'The order list did not finish loading. Try again.',
        },
      );
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/m3-${screen.name}-error-760.png'),
        ),
      );
    }, skip: !enabled);
  }
}

const _goldenKey = ValueKey('SalesDocumentsGolden');

/// The clock every PNG is judged by, so a quotation's "Expired" badge is the
/// same fact in the PNG as it was when this test was written.
final DateTime _today = DateTime(2026, 10, 30);

/// The two screens, by the name their PNGs carry. `kind` is the read a screen's
/// error PNG fails: both pages read one viewmodel, so a failure has to be raised
/// by the read the screen actually shows, or the orders PNG would report the
/// quotations read.
final _screens = [
  _Screen('quotations', SalesDocumentKind.quotation, _quotationsPage),
  _Screen('orders', SalesDocumentKind.order, _ordersPage),
];

Widget _quotationsPage() => SalesQuotationsPage(now: () => _today);

Widget _ordersPage() => const SalesOrdersPage();

class _Screen {
  const _Screen(this.name, this.kind, this.build);

  final String name;
  final SalesDocumentKind kind;
  final Widget Function() build;
}

/// Answers from memory; nothing here touches a server.
class _StubSalesService extends SalesService {
  _StubSalesService({
    this.quotations = const [],
    this.orders = const [],
    this.failure,
    this.failingKind = SalesDocumentKind.quotation,
  });

  final List<QuotationRecord> quotations;
  final List<SalesOrderRow> orders;

  /// When set, the read for [failingKind] fails with this message.
  final String? failure;
  final SalesDocumentKind failingKind;

  void _failIf(SalesDocumentKind kind) {
    final message = failure;
    if (message != null && kind == failingKind) {
      throw SalesServiceException(message);
    }
  }

  @override
  Future<List<QuotationRecord>> fetchQuotations() async {
    _failIf(SalesDocumentKind.quotation);
    return quotations;
  }

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() async {
    _failIf(SalesDocumentKind.order);
    return orders;
  }
}

/// The customer names the rows are joined against, by id.
class _StubCustomerService extends CustomerService {
  @override
  Future<List<Customer>> fetchCustomers() async => const [
    Customer(
      id: 3,
      name: 'Dela Cruz Construction',
      customerType: 'CONSTRUCTION_FIRM',
    ),
    Customer(
      id: 4,
      name: 'Northern Mindanao Builders and Hardware Trading Corporation',
      customerType: 'CONSTRUCTION_FIRM',
    ),
    Customer(id: 5, name: 'Reyes Trading', customerType: 'RETAIL'),
    Customer(id: 6, name: 'Bunawan Hardware', customerType: 'RETAIL'),
  ];
}

/// Four quotations covering what the layout must survive: a live one, one past
/// its valid date (the defect this card fixes), a draft, and an accepted one
/// carrying a SEVEN DIGIT total behind a long customer name.
List<QuotationRecord> _quotations() => const [
  QuotationRecord(
    id: 1,
    number: 'QT-20261030-0001',
    customerId: 3,
    status: 'SENT',
    validUntil: '2026-11-29',
    createdAt: '2026-10-30T08:00:00Z',
    items: [QuotationLineItem(variantUomId: 42, qty: 8, unitPrice: 185)],
  ),
  QuotationRecord(
    id: 2,
    number: 'QT-20261028-0004',
    customerId: 4,
    status: 'SENT',
    validUntil: '2026-10-27',
    createdAt: '2026-10-28T09:15:00Z',
    items: [QuotationLineItem(variantUomId: 42, qty: 1400, unitPrice: 820)],
  ),
  QuotationRecord(
    id: 3,
    number: 'QT-20261025-0002',
    customerId: 5,
    status: 'DRAFT',
    validUntil: '2026-12-31',
    createdAt: '2026-10-25T13:40:00Z',
    items: [QuotationLineItem(variantUomId: 42, qty: 4, unitPrice: 2400)],
  ),
  QuotationRecord(
    id: 4,
    number: 'QT-20261020-0001',
    customerId: 6,
    status: 'ACCEPTED',
    validUntil: '2026-12-15',
    createdAt: '2026-10-20T10:05:00Z',
    items: [QuotationLineItem(variantUomId: 42, qty: 2, unitPrice: 12400.25)],
  ),
];

/// Four orders, one per status, one of them a seven digit total.
List<SalesOrderRow> _orders() => const [
  SalesOrderRow(
    id: 1,
    number: 'SO-20261030-0002',
    customerId: 3,
    quotationId: 1,
    status: 'CONFIRMED',
    createdAt: '2026-10-30T08:30:00Z',
    items: [OrderLineItem(variantUomId: 42, qty: 24, unitPrice: 175)],
  ),
  SalesOrderRow(
    id: 2,
    number: 'SO-20261029-0001',
    customerId: 4,
    quotationId: 2,
    status: 'PROCESSING',
    createdAt: '2026-10-29T09:00:00Z',
    items: [OrderLineItem(variantUomId: 42, qty: 1400, unitPrice: 820)],
  ),
  SalesOrderRow(
    id: 3,
    number: 'SO-20261028-0003',
    customerId: 5,
    quotationId: null,
    status: 'READY',
    createdAt: '2026-10-28T11:20:00Z',
    items: [OrderLineItem(variantUomId: 42, qty: 5, unitPrice: 2500)],
  ),
  SalesOrderRow(
    id: 4,
    number: 'SO-20261027-0005',
    customerId: 6,
    quotationId: null,
    status: 'COMPLETED',
    createdAt: '2026-10-27T15:45:00Z',
    items: [OrderLineItem(variantUomId: 42, qty: 2, unitPrice: 44500.25)],
  ),
];

SalesModuleViewmodel _viewmodel({
  required SalesDocumentKind kind,
  bool empty = false,
  String? failure,
}) {
  return SalesModuleViewmodel(
    service: _StubSalesService(
      quotations: empty ? const [] : _quotations(),
      orders: empty ? const [] : _orders(),
      failure: failure,
      failingKind: kind,
    ),
    customerService: _StubCustomerService(),
  );
}

Future<void> _pump(
  WidgetTester tester,
  _Screen screen,
  Size size, {
  bool empty = false,
  String? failure,
}) async {
  final viewmodel = _viewmodel(
    kind: screen.kind,
    empty: empty,
    failure: failure,
  );
  await viewmodel.load();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _goldenKey,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<SalesModuleViewmodel>.value(value: viewmodel),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          // Only the goldens: lets a peso sign fall back to the system font the
          // app itself uses, because the brand fonts stop at Latin.
          theme: AppTheme.lightTheme.copyWith(
            textTheme: AppTheme.lightTheme.textTheme.apply(
              fontFamilyFallback: const [_pesoFallbackFamily],
            ),
          ),
          home: screen.build(),
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
