import 'package:client/data/models/shift.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/pos/widgets/pos_product_browser.dart';
import 'package:client/features/pos/widgets/pos_transaction_cart.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The shift GATE on the till (decision 06: `process_sale` refuses a sale with
/// no open shift).
///
/// What this pins, and why it is not a viewmodel concern: a sale rung outside a
/// shift is either rejected by the server or — worse, on an older server —
/// accepted into NO Z-reading, so the drawer never balances. The gate must
/// therefore remove the till, not merely warn: the product browser and cart are
/// never built while no shift is open.
class _StubShifts extends ShiftService {
  int currentCalls = 0;
  int openCalls = 0;
  double? openedWith;
  Object? failCurrent;
  Object? failOpen;
  Shift? current;

  @override
  Future<Shift?> fetchCurrent() async {
    currentCalls++;
    if (failCurrent != null) throw failCurrent!;
    return current;
  }

  @override
  Future<Shift> openShift(double openingFloat) async {
    openCalls++;
    openedWith = openingFloat;
    if (failOpen != null) throw failOpen!;
    current = _openShift(openingFloat);
    return current!;
  }
}

Shift _openShift(double openingFloat) => Shift(
  id: 1,
  cashierName: 'Ana Cruz',
  status: Shift.openStatus,
  openingFloat: openingFloat,
  closingCount: null,
  openedAt: DateTime(2026, 10, 21, 8),
  closedAt: null,
  notes: '',
  zReading: null,
);

class _FailingProductsRepository extends ProductsRepository {
  _FailingProductsRepository() : super(ProductsService());

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      throw const ProductsServiceException('Cannot connect.');
}

class _FailingInventoryRepository extends InventoryRepository {
  _FailingInventoryRepository() : super(InventoryService());

  @override
  Future<List<SystemAlert>> loadAlerts() async =>
      throw const InventoryServiceException('Cannot connect.');

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => [];
}

Future<void> _pump(WidgetTester tester, ShiftViewmodel shift) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final inventory = InventoryViewmodel(
    products: _FailingProductsRepository(),
    inventory: _FailingInventoryRepository(),
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<ProductTrackingViewmodel>.value(
            value: ProductTrackingViewmodel(),
          ),
        ],
        child: MaterialApp(
          home: PosTransactionPage(
            viewmodel: PosTransactionViewmodel(
              inventory,
              ProductTrackingViewmodel(),
            ),
            shiftViewmodel: shift,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with no open shift the till is NOT built at all', (
    tester,
  ) async {
    final service = _StubShifts();
    await _pump(tester, ShiftViewmodel(service: service));

    expect(find.text('Open a shift to start selling'), findsOneWidget);
    expect(
      find.byType(PosProductBrowser),
      findsNothing,
      reason: 'a product browser behind the gate would let a sale be rung',
    );
    expect(find.byType(PosTransactionCart), findsNothing);
    expect(
      service.currentCalls,
      1,
      reason: 'the page must ASK on open, not assume',
    );
  });

  testWidgets('entering the float opens the shift and reveals the till', (
    tester,
  ) async {
    final service = _StubShifts();
    await _pump(tester, ShiftViewmodel(service: service));

    await tester.enterText(find.byType(TextField), '5000');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Open shift'));
    await tester.pumpAndSettle();

    expect(service.openCalls, 1);
    expect(service.openedWith, 5000);
    expect(find.text('Open a shift to start selling'), findsNothing);
    expect(
      find.byType(PosProductBrowser),
      findsOneWidget,
      reason: 'the till activates only after the shift exists',
    );
    expect(find.textContaining('Shift open'), findsOneWidget);
  });

  testWidgets('an unreadable float cannot open a shift', (tester) async {
    final service = _StubShifts();
    await _pump(tester, ShiftViewmodel(service: service));

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Open shift'),
    );
    expect(button.onPressed, isNull);

    await tester.enterText(find.byType(TextField), '-20');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Open shift'))
          .onPressed,
      isNull,
      reason: 'money that cannot be in a drawer is a typo, not a float',
    );
    expect(service.openCalls, 0);
  });

  testWidgets('a failed shift check shows a retry, NOT the open-shift form', (
    tester,
  ) async {
    // A message the catalogue banner cannot also produce: both banners are on
    // screen at once, and the assertion has to name the shift one.
    final service = _StubShifts()
      ..failCurrent = const ShiftServiceException('The shift could not be read.');
    await _pump(tester, ShiftViewmodel(service: service));

    expect(find.text('The shift could not be read.'), findsOneWidget);
    expect(
      find.text('Open a shift to start selling'),
      findsNothing,
      reason:
          'a failed check may still mean a shift is open on the server, and '
          'opening a second one is refused (or double-counts the drawer)',
    );
    expect(find.byType(PosProductBrowser), findsNothing);

    service.failCurrent = null;
    service.current = _openShift(5000);
    // The catalogue banner is on screen too, so the retry must be the shift's own.
    final shiftBanner = find.ancestor(
      of: find.text('The shift could not be read.'),
      matching: find.byType(LiveLoadErrorBanner),
    );
    await tester.tap(
      find.descendant(of: shiftBanner, matching: find.text('Retry')),
    );
    await tester.pumpAndSettle();

    expect(service.currentCalls, greaterThan(1));
    expect(find.byType(PosProductBrowser), findsOneWidget);
  });

  testWidgets('the open shift is visible and closable from the till', (
    tester,
  ) async {
    final service = _StubShifts()..current = _openShift(5000);
    await _pump(tester, ShiftViewmodel(service: service));

    expect(find.textContaining('₱5000.00'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Close shift'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Close shift'));
    await tester.pumpAndSettle();

    expect(find.text('Cash counted'), findsOneWidget);
  });
}
