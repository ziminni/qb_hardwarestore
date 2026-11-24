// The sidebar tests next door pin an index at SOURCE level: the number a page
// passes must resolve, through the registry, back to that page's own route. None
// of them RENDERS a page, so none of them would notice a shell that highlights
// a row nobody declared — the registry lookup can be right while the row drawn
// as selected is the page above it.
//
// This file closes that gap the blunt way: pump the PRODUCTION page inside its
// shell (with stub viewmodels, so no server is involved) and read the sidebar
// row the shell actually marked selected. One highlighted row, and its label is
// the page's own. A mis-highlight shows up here as "Project requests", which is
// exactly the Task 19 / decision 13 regression this is meant to catch.

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/stock_transfer.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/payables_repository.dart';
import 'package:client/data/repositories/stock_transfer_repository.dart';
import 'package:client/data/repositories/storage_location_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/delivery_service.dart';
import 'package:client/data/services/user_service.dart';
import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:client/features/admin/views/admin_user_management_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/deliveries/viewmodels/deliveries_viewmodel.dart';
import 'package:client/features/deliveries/views/deliveries_page.dart';
import 'package:client/features/payables/viewmodels/payables_viewmodel.dart';
import 'package:client/features/payables/views/payables_page.dart';
import 'package:client/features/transfers/viewmodels/transfers_viewmodel.dart';
import 'package:client/features/transfers/views/transfers_page.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Empty answers, so each page renders its real shell without a request.
class _StubPayablesRepository extends PayablesRepository {
  @override
  Future<List<SupplierBill>> fetchBills({
    int? supplierId,
    SupplierBillStatus? status,
    bool overdueOnly = false,
  }) async => const [];

  @override
  Future<List<SupplierPayable>> fetchSummary() async => const [];
}

class _StubDeliveriesService extends DeliveryService {
  @override
  Future<List<Delivery>> fetchAll({
    DeliveryStatus? status,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async => const [];
}

class _StubTransfersRepository extends StockTransferRepository {
  @override
  Future<List<StockTransfer>> fetchAll() async => const [];
}

class _StubLocationsRepository extends StorageLocationRepository {
  @override
  Future<List<StorageLocation>> fetchAll() async => const [];
}

class _StubUsersService extends UserService {
  @override
  Future<List<User>> fetchUsers({String? search}) async => const [];

  @override
  Future<UserStats> fetchUserStats() async =>
      const UserStats(total: 0, active: 0, inactive: 0, rolesAssigned: 0);
}

/// The page inside the frame every signed-in screen gets, the same wrappers the
/// per-page widget tests use.
///
/// Tall on purpose: the sidebar builds its rows lazily, and a row below the fold
/// would be missing rather than unhighlighted.
Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewmodel>(
          create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        ),
      ],
      child: MaterialApp(theme: AppTheme.lightTheme, home: page),
    ),
  );
  await tester.pumpAndSettle();
}

/// The labels of the rows the sidebar marked selected. Read from the rendered
/// `ListTile.selected` flag, i.e. what the reader sees as the active row.
List<String> _highlightedRows(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(
    find.descendant(
      of: find.byType(SharedSidebar),
      matching: find.byType(ListTile),
    ),
  ))
    if (tile.selected) (tile.title! as Text).data!,
];

void main() {
  // The shell remembers the sidebar as a collapsed icon RAIL by default
  // (`SidebarCollapsePreference.cached => _cached ?? true`), and a rail has no
  // row labels at all. The expanded sidebar is the mode this file reads, so the
  // stored choice is set to it.
  setUp(
    () => SharedPreferences.setMockInitialValues({'sidebar_collapsed': false}),
  );

  testWidgets('/sales/payables highlights Payables', (tester) async {
    await _pump(
      tester,
      SalesPayablesPage(
        viewmodel: PayablesViewmodel(repository: _StubPayablesRepository()),
      ),
    );

    expect(_highlightedRows(tester), [
      'Payables',
    ], reason: 'the row above it is Project requests (decision 13)');
    expect(
      AppDestinations.labelsFor(AppAreas.sales),
      containsAll(['Project requests', 'Payables']),
      reason: 'guards against the assertion passing on a menu that changed',
    );
  });

  testWidgets('/sales/deliveries highlights Deliveries', (tester) async {
    await _pump(
      tester,
      SalesDeliveriesPage(
        viewmodel: DeliveriesViewmodel(service: _StubDeliveriesService()),
      ),
    );

    expect(_highlightedRows(tester), [
      'Deliveries',
    ], reason: 'the row above it is Payables');
  });

  testWidgets('/sales/transfers highlights Transfers', (tester) async {
    await _pump(
      tester,
      SalesTransfersPage(
        viewmodel: TransfersViewmodel(
          repository: _StubTransfersRepository(),
          locations: _StubLocationsRepository(),
        ),
      ),
    );

    expect(_highlightedRows(tester), [
      'Transfers',
    ], reason: 'the row above it is Deliveries');
  });

  testWidgets('/sales/staff highlights Staff', (tester) async {
    await _pump(
      tester,
      AdminUserManagementPage(
        viewmodel: AdminUsersViewmodel(users: _StubUsersService()),
        inSalesShell: true,
      ),
    );

    expect(_highlightedRows(tester), [
      'Staff',
    ], reason: 'the row above it is Reports');
  });
}
