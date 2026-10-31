// Card K7 (UI refresh): Purchases and Suppliers.
//
// Three things the card changes, each pinned here by BEHAVIOUR:
//   * the status dropdown becomes chips that carry their own counts, so the
//     reader sees "Ordered 3" before narrowing anything,
//   * both lists are the shared `DataPanel` (table on a wide window, cards on a
//     narrow one), with money, dates and status words from the shared formatters,
//   * the New purchase order dialog sizes itself to its content instead of
//     `screen height - 190`, so it fits at 1366x768 and at 760 px wide.
//
// The dialog test measures the dialog at two window heights with the SAME
// content: a formula makes the height follow the window, a content sized dialog
// keeps it equal.

import 'package:client/data/models/purchase_draft.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/supplier_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/supplier_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/views/purchases_page.dart';
import 'package:client/features/suppliers/views/suppliers_page.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

Supplier _supplier({
  required int id,
  required String companyName,
  String contactPerson = '',
  String phone = '',
  String email = '',
  String address = '',
  bool isActive = true,
}) => Supplier(
  id: id,
  companyName: companyName,
  contactPerson: contactPerson,
  phone: phone,
  email: email,
  address: address,
  isActive: isActive,
);

PurchaseOrder _purchase({
  required int id,
  required int supplierId,
  required PurchaseStatus status,
  double quantity = 20,
  double received = 0,
}) => PurchaseOrder(
  id: id,
  supplierId: supplierId,
  supplierName: '',
  orderDate: DateTime(2026, 10, 20),
  expectedDelivery: DateTime(2026, 10, 25),
  status: status,
  createdBy: 'Ana Lopez',
  notes: 'Replenishment',
  items: [
    PurchaseItem(
      productName: '',
      variantName: 'Portland Cement 40kg',
      sku: '',
      quantity: quantity,
      receivedQuantity: received,
      unitCost: 240,
    ),
  ],
);

class _StubSupplierRepository extends SupplierRepository {
  _StubSupplierRepository({
    this.suppliers = const [],
    this.purchases = const [],
  });

  List<Supplier> suppliers;
  List<PurchaseOrder> purchases;
  String? failure;
  int supplierCalls = 0;

  @override
  Future<List<Supplier>> fetchSuppliers() async {
    supplierCalls++;
    final failure = this.failure;
    if (failure != null) throw SupplierServiceException(failure);
    return suppliers;
  }

  @override
  Future<List<PurchaseOrder>> fetchPurchaseOrders() async {
    final failure = this.failure;
    if (failure != null) throw SupplierServiceException(failure);
    return purchases;
  }

  final List<Map<String, dynamic>> patchedSuppliers = [];
  final List<int> placedOrders = [];

  @override
  Future<void> patchSupplier(int id, Map<String, dynamic> body) async {
    patchedSuppliers.add({'id': id, ...body});
    suppliers = [
      for (final supplier in suppliers)
        supplier.id == id
            ? supplier.copyWith(isActive: body['is_active'] as bool?)
            : supplier,
    ];
  }

  @override
  Future<int> createPurchaseOrder(PurchaseOrderDraft draft) async => 77;

  @override
  Future<void> placePurchaseOrder(int id) async => placedOrders.add(id);
}

Widget _app(
  Widget page,
  SupplierRepository repository, {
  InventoryViewmodel? inventory,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthViewmodel>(
        create: (_) => AuthViewmodel(AuthRepository(AuthService())),
      ),
      ChangeNotifierProvider<SuppliersPurchasesViewmodel>(
        create: (_) => SuppliersPurchasesViewmodel(repository: repository),
      ),
      if (inventory != null)
        ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
    ],
    child: MaterialApp(home: page),
  );
}

void _sizeUp(WidgetTester tester, {Size size = const Size(1600, 1200)}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Finds a chip by its label INSIDE the filter bar: a chip label can equal a row
/// badge ("Complete"), so the scope is what makes the finder unambiguous.
Finder _chip(String label) =>
    find.descendant(of: find.byType(FilterBar), matching: find.text(label));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Purchases page', () {
    testWidgets('status chips carry their counts over the loaded orders', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _StubSupplierRepository(
        suppliers: [_supplier(id: 9, companyName: 'Cebu Steel Works')],
        purchases: [
          _purchase(id: 41, supplierId: 9, status: PurchaseStatus.ordered),
          _purchase(id: 40, supplierId: 9, status: PurchaseStatus.complete),
          _purchase(id: 42, supplierId: 9, status: PurchaseStatus.ordered),
        ],
      );
      await tester.pumpWidget(_app(const PurchasesPage(), repository));
      await tester.pumpAndSettle();

      expect(_chip('All statuses 3'), findsOneWidget);
      expect(_chip('Ordered 2'), findsOneWidget);
      // A zero count is still shown: "no drafts" is information, not noise.
      expect(_chip('Draft 0'), findsOneWidget);
      expect(_chip('Complete 1'), findsOneWidget);
    });

    testWidgets(
      'a chip narrows the list, and a zero chip says why it is empty',
      (tester) async {
        _sizeUp(tester);
        final repository = _StubSupplierRepository(
          suppliers: [_supplier(id: 9, companyName: 'Cebu Steel Works')],
          purchases: [
            _purchase(id: 41, supplierId: 9, status: PurchaseStatus.ordered),
            _purchase(id: 40, supplierId: 9, status: PurchaseStatus.complete),
          ],
        );
        await tester.pumpWidget(_app(const PurchasesPage(), repository));
        await tester.pumpAndSettle();

        await tester.tap(_chip('Complete 1'));
        await tester.pumpAndSettle();

        expect(find.text('PO-40'), findsOneWidget);
        expect(find.text('PO-41'), findsNothing);

        await tester.tap(_chip('Draft 0'));
        await tester.pumpAndSettle();

        expect(
          find.text('No purchase orders match these filters.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'orders render in a DataPanel with money, date and status words',
      (tester) async {
        _sizeUp(tester, size: const Size(1440, 1000));
        final repository = _StubSupplierRepository(
          suppliers: [_supplier(id: 9, companyName: 'Cebu Steel Works')],
          purchases: [
            _purchase(
              id: 41,
              supplierId: 9,
              status: PurchaseStatus.ordered,
              quantity: 20000,
            ),
          ],
        );
        await tester.pumpWidget(_app(const PurchasesPage(), repository));
        await tester.pumpAndSettle();

        expect(find.byType(DataPanel<PurchaseOrder>), findsOneWidget);
        // 20,000 x 240 = 4,800,000: seven digits, grouped and right aligned.
        expect(find.text('₱4,800,000.00'), findsOneWidget);
        expect(find.text('Oct 20, 2026'), findsWidgets);
        // The status is words, not a colour or a code.
        expect(find.text('Ordered'), findsWidgets);
      },
    );

    testWidgets(
      'a draft row offers Place order, an ordered row offers Receive',
      (tester) async {
        _sizeUp(tester, size: const Size(1440, 1000));
        final repository = _StubSupplierRepository(
          suppliers: [_supplier(id: 9, companyName: 'Cebu Steel Works')],
          purchases: [
            _purchase(id: 41, supplierId: 9, status: PurchaseStatus.ordered),
            _purchase(id: 43, supplierId: 9, status: PurchaseStatus.draft),
          ],
        );
        await tester.pumpWidget(_app(const PurchasesPage(), repository));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Place purchase order'), findsOneWidget);
        expect(find.byTooltip('Receive purchase order'), findsOneWidget);
        expect(find.byTooltip('Cancel purchase order'), findsNWidgets(2));
      },
    );
  });

  group('New purchase order dialog', () {
    Future<void> pumpDialog(WidgetTester tester, Size window) async {
      _sizeUp(tester, size: window);
      final inventory = InventoryViewmodel(
        products: FakeProductsRepository(
          products: [
            product(
              id: 6,
              name: 'Portland Cement',
              variants: [
                variant(
                  id: 8,
                  productId: 6,
                  name: '40 kg bag',
                  baseUomCode: 'BAG',
                ),
              ],
            ),
          ],
        ),
        inventory: FakeInventoryRepository(),
        catalogue: FakeCatalogueRepository(),
      );
      await inventory.load();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PurchasesFormDialog(
                suppliers: [_supplier(id: 9, companyName: 'Cebu Steel Works')],
                products: inventory.products,
                costFor: (_) => 240,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('its height follows the content, not the window height', (
      tester,
    ) async {
      await pumpDialog(tester, const Size(1400, 960));
      final tall = tester.getSize(find.byType(Form)).height;

      await pumpDialog(tester, const Size(1400, 820));
      final shorter = tester.getSize(find.byType(Form)).height;

      expect(tester.takeException(), isNull);
      // A `screen height - N` formula makes these two differ with the same
      // content on screen; a content sized dialog keeps them equal.
      expect(shorter, tall);
    });

    testWidgets('it fits at 1366x768 with its actions reachable', (
      tester,
    ) async {
      await pumpDialog(tester, const Size(1366, 768));

      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.byType(Form));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(768));
      expect(find.text('Place order').hitTestable(), findsOneWidget);
      expect(find.text('Save draft').hitTestable(), findsOneWidget);
    });

    testWidgets('it fits at 760 px wide and keeps its actions reachable', (
      tester,
    ) async {
      await pumpDialog(tester, const Size(760, 900));

      expect(tester.takeException(), isNull);
      final rect = tester.getRect(find.byType(Form));
      expect(rect.width, lessThanOrEqualTo(760));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(find.text('Place order').hitTestable(), findsOneWidget);
    });
  });

  group('Suppliers page', () {
    testWidgets('suppliers render in a DataPanel with open orders and status', (
      tester,
    ) async {
      _sizeUp(tester, size: const Size(1440, 1000));
      final repository = _StubSupplierRepository(
        suppliers: [
          _supplier(
            id: 7,
            companyName: 'Bohol Cement Traders',
            contactPerson: 'Rina Lim',
            phone: '0917 000 1111',
            email: 'orders@boholcement.ph',
            address: 'Tagbilaran City',
          ),
          _supplier(id: 9, companyName: 'Cebu Steel Works', isActive: false),
        ],
        purchases: [
          _purchase(id: 41, supplierId: 7, status: PurchaseStatus.ordered),
          _purchase(id: 42, supplierId: 7, status: PurchaseStatus.complete),
          _purchase(id: 43, supplierId: 9, status: PurchaseStatus.cancelled),
        ],
      );
      await tester.pumpWidget(_app(const SuppliersPage(), repository));
      await tester.pumpAndSettle();

      expect(find.byType(DataPanel<Supplier>), findsOneWidget);
      expect(find.text('Bohol Cement Traders'), findsOneWidget);
      expect(find.text('Rina Lim'), findsOneWidget);
      // Only the order still in flight counts: one ordered, one complete and
      // one cancelled leave Bohol with a single open order.
      expect(find.text('Open orders'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      // The active flag is words, not a chip with no state.
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
    });

    testWidgets('New order opens the purchase form for THAT supplier', (
      tester,
    ) async {
      _sizeUp(tester, size: const Size(1600, 1200));
      final inventory = InventoryViewmodel(
        products: FakeProductsRepository(
          products: [
            product(
              id: 6,
              name: 'Portland Cement',
              variants: [variant(id: 8, productId: 6, name: '40 kg bag')],
            ),
          ],
        ),
        inventory: FakeInventoryRepository(),
        catalogue: FakeCatalogueRepository(),
      );
      await inventory.load();
      final repository = _StubSupplierRepository(
        suppliers: [_supplier(id: 7, companyName: 'Bohol Cement Traders')],
      );
      await tester.pumpWidget(
        _app(const SuppliersPage(), repository, inventory: inventory),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New order'));
      await tester.pumpAndSettle();

      expect(find.byType(PurchasesFormDialog), findsOneWidget);
      final dropdown = tester.widget<DropdownButtonFormField<int>>(
        find.byType(DropdownButtonFormField<int>),
      );
      expect(dropdown.initialValue, 7);
    });

    testWidgets('the active toggle still writes is_active through the server', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _StubSupplierRepository(
        suppliers: [_supplier(id: 7, companyName: 'Bohol Cement Traders')],
      );
      await tester.pumpWidget(_app(const SuppliersPage(), repository));
      await tester.pumpAndSettle();

      // Reachable, not scrolled off the right edge of a sideways table.
      expect(
        find.byTooltip('Deactivate supplier').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Deactivate supplier'));
      await tester.pumpAndSettle();

      expect(repository.patchedSuppliers.single, {'id': 7, 'is_active': false});
      expect(find.text('Inactive'), findsOneWidget);
    });
  });
}
