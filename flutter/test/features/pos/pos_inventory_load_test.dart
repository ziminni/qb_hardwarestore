import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _FailingProductsRepository extends ProductsRepository {
  _FailingProductsRepository() : super(ProductsService());

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      throw const ProductsServiceException('Cannot connect to the BuildPro server.');
}

class _FailingInventoryRepository extends InventoryRepository {
  _FailingInventoryRepository() : super(InventoryService());

  @override
  Future<List<SystemAlert>> loadAlerts() async =>
      throw const InventoryServiceException('Cannot connect.');

  @override
  Future<List<StockAdjustment>> loadAdjustments() async =>
      [];
}

/// The till only renders inside an open shift (decision 06), so the catalogue
/// error below would otherwise be hidden behind the open-shift prompt.
class _OpenShift extends ShiftService {
  @override
  Future<Shift?> fetchCurrent() async => Shift(
    id: 1,
    cashierName: 'Ana Cruz',
    status: Shift.openStatus,
    openingFloat: 5000,
    closingCount: null,
    openedAt: DateTime(2026, 10, 21, 8),
    closedAt: null,
    notes: '',
    zReading: null,
  );
}

void main() {
  testWidgets('a failed catalogue load shows the error with a retry', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
              shiftViewmodel: ShiftViewmodel(service: _OpenShift()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot connect'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });
}
