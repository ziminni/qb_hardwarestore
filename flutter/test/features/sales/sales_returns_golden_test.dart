@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/returns_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/views/sales_returns_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The visual check for card M5 (00-shared/VERIFY.md, fallback 3): the Store
/// Manager's Returns screen, with the REAL fonts and the REAL theme, written as
/// PNGs into the SDD folder so the layout can be looked at without a browser.
///
/// Same opt-in mechanism as the shared components' golden test, so the normal
/// suite never fails on a font or platform difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/sales/sales_returns_golden_test.dart
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

  for (final entry in const [
    ('1440', Size(1440, 900)),
    ('1100', Size(1100, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('returns list at ${entry.$1} px', (tester) async {
      await _pump(tester, entry.$2);
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/m5-list-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('returns empty at 760 px', (tester) async {
    await _pump(tester, const Size(760, 900), rows: const []);
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/m5-empty-760.png')),
    );
  }, skip: !enabled);

  testWidgets('returns error at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      failure: 'The returns list did not finish loading. Try again.',
    );
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/m5-error-760.png')),
    );
  }, skip: !enabled);

  testWidgets('unlinked return dialog at 760 px', (tester) async {
    await _pump(tester, const Size(760, 900), openDialog: true);
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/m5-dialog-760.png')),
    );
  }, skip: !enabled);
}

const _goldenKey = ValueKey('SalesReturnsGolden');

const String _pesoFallbackFamily = 'PesoFallback';

const List<String> _pesoFontCandidates = [
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  '/usr/share/fonts/TTF/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  'C:/Windows/Fonts/arial.ttf',
];

/// Answers `fetchTransactions` from memory; nothing here touches a server.
class _StubSalesService extends SalesService {
  _StubSalesService({this.rows = const [], this.error});

  final List<TransactionRecord> rows;
  final String? error;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async {
    final failure = error;
    if (failure != null) throw SalesServiceException(failure);
    return rows;
  }
}

/// The dialog's three reads, answered from memory, so the PNG shows a filled
/// form rather than a spinner.
class _StubReturnsService extends ReturnsService {
  @override
  Future<ReturnResult> postUnlinkedReturn({
    required int customerId,
    required String reason,
    required String paymentMethod,
    required List<ReturnRequestLine> lines,
  }) async => ReturnResult.fromJson(const {
    'transaction_no': 'RTN-20261026-0001',
    'refund_summary': {
      'return_value': '300.00',
      'debt_reduced': '200.00',
      'cash_refund': '100.00',
      'refund_method': 'CASH',
      'ledger_id': 7,
      'ledger_balance': '0.00',
    },
  });
}

class _StubCustomerService extends CustomerService {
  @override
  Future<List<Customer>> fetchCustomers() async => const [
    Customer(id: 3, name: 'Dela Cruz Construction', customerType: 'FIRM'),
    Customer(
      id: 4,
      name: 'Northern Mindanao Builders and Hardware Trading Corporation',
      customerType: 'FIRM',
    ),
  ];
}

class _StubProductsService extends ProductsService {
  @override
  Future<ProductsSnapshot> fetchCatalogue() async => const ProductsSnapshot(
    products: [
      Product(
        id: 1,
        categoryId: 1,
        categoryName: 'Cement',
        brandId: 1,
        brandName: 'Rhino',
        baseName: 'Portland Cement',
        description: '',
        imageUrl: '',
        isActive: true,
        variants: [
          ProductVariant(
            id: 5,
            productId: 1,
            baseUomId: 1,
            minStockThreshold: 1,
            maxStockLevel: 100,
            variantName: '40kg',
            baseUomCode: 'BAG',
            isActive: true,
            sellingUoms: [
              VariantUom(
                id: 8,
                variantId: 5,
                uomId: 1,
                uomCode: 'BAG',
                uomName: 'Bag',
                barcodeQr: '',
                conversionFactor: 1,
                defaultSellingPrice: 300,
              ),
            ],
          ),
        ],
      ),
    ],
    batches: [],
  );
}

/// Four posted returns covering what the list must survive: a linked one with
/// two lines, an UNLINKED one (the manager's own correction), a rejected one,
/// and one carrying a SEVEN DIGIT refund behind a long selling-unit code.
List<TransactionRecord> _returns() => [
  _return(
    id: 10,
    no: 'RTN-20261030-0002',
    at: DateTime(2026, 10, 30, 14, 14),
    original: 91,
    lines: [_line('BAG', 2, 250), _line('TILE-60', 1, 320)],
  ),
  _return(
    id: 11,
    no: 'RTN-20261030-0001',
    at: DateTime(2026, 10, 30, 9, 5),
    lines: [_line('CEM-40KG', 1200, 950)],
  ),
  _return(
    id: 12,
    no: 'RTN-20261029-0004',
    at: DateTime(2026, 10, 29, 16, 40),
    original: 88,
    status: 'VOID',
    lines: [_line('PIPE-2IN', 1, 240)],
  ),
  _return(
    id: 13,
    no: 'RTN-20261029-0003',
    at: DateTime(2026, 10, 29, 11, 20),
    original: 87,
    lines: [_line('MARINE-PLYWOOD-3QTR-4X8-SHEET', 6, 1480.50)],
  ),
];

TransactionRecord _return({
  required int id,
  required String no,
  required DateTime at,
  int? original,
  String status = 'COMPLETED',
  required List<TransactionLineItem> lines,
}) => TransactionRecord(
  id: id,
  transactionNo: no,
  transDate: at,
  customerId: 3,
  customerName: 'Dela Cruz Construction',
  cashierName: 'Ana Reyes',
  source: 'RETURN',
  originalTransactionId: original,
  status: status,
  grandTotal: lines.fold<double>(0, (sum, line) => sum + line.subtotal),
  items: lines,
  payments: const [],
);

TransactionLineItem _line(String code, double qty, double unitPrice) =>
    TransactionLineItem(
      variantUomId: 42,
      variantUomCode: code,
      qty: qty,
      unitPrice: unitPrice,
      subtotal: qty * unitPrice,
    );

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  List<TransactionRecord>? rows,
  String? failure,
  bool openDialog = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // A signed-in Store Manager: the page's unlinked action is his, so the PNG
  // has to be taken as him or the header action would be missing from it.
  final auth = AuthViewmodel(AuthRepository(AuthService()))
    ..user = User(
      id: 1,
      username: 'manager',
      email: 'manager@demo.ph',
      fullName: 'Ana Reyes',
      role: Role(id: 2, name: 'sales', displayName: 'Store Manager'),
    );

  await tester.pumpWidget(
    RepaintBoundary(
      key: _goldenKey,
      child: ChangeNotifierProvider<AuthViewmodel>.value(
        value: auth,
        child: ChangeNotifierProvider<InventorySalesViewmodel>.value(
          value: InventorySalesViewmodel(
            service: _StubSalesService(
              rows: rows ?? _returns(),
              error: failure,
            ),
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme.copyWith(
              textTheme: AppTheme.lightTheme.textTheme.apply(
                fontFamilyFallback: const [_pesoFallbackFamily],
              ),
            ),
            home: SalesReturnsPage(
              returnsService: _StubReturnsService(),
              customerService: _StubCustomerService(),
              productsService: _StubProductsService(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  if (openDialog) {
    await tester.tap(find.widgetWithText(FilledButton, 'Unlinked return'));
    await tester.pumpAndSettle();
    // A form as a manager would leave it: the customer chosen and the reason
    // typed, so the PNG shows the real field heights and the post button.
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dela Cruz Construction').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for the return (required)'),
      'Bag burst in transit',
    );
    await tester.pumpAndSettle();
  }

  // A layout overflow would paint yellow stripes into the PNG; a throw here
  // names it instead of shipping it.
  expect(tester.takeException(), isNull);
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
