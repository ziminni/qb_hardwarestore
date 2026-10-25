// Decision D-02 (admin-workflow): the Suppliers and Purchases screens used to
// read hardcoded fixtures inside `SuppliersPurchasesViewmodel` — six vendors and
// five POs that no server had ever heard of, with a Save button that mutated the
// list locally and a snackbar that admitted it ("Supplier saved in mock data.").
//
// They now read `GET /api/v1/suppliers/` and `GET /api/v1/purchase-orders/`.
// These tests pin the three things that make that real:
//   * the tables show the REPOSITORY's rows, not the fixtures,
//   * a PO's supplier name is joined from the loaded suppliers, because
//     `PurchaseOrderSerializer` sends the id only (D-02 refused a backend
//     change for this),
//   * a failure names itself and the retry actually re-fetches,
//   * the mock-creating controls are gone, not greyed.

import 'package:client/data/models/purchase_draft.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/supplier_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/supplier_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/views/purchases_page.dart';
import 'package:client/features/suppliers/views/suppliers_page.dart';
import 'package:client/features/suppliers/widgets/purchases_details_dialog.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
  DateTime? orderDate,
}) => PurchaseOrder(
  id: id,
  supplierId: supplierId,
  supplierName: '',
  orderDate: orderDate ?? DateTime(2026, 10, 20),
  expectedDelivery: DateTime(2026, 10, 25),
  status: status,
  createdBy: 'Ana Lopez',
  notes: 'Replenishment',
  items: const [
    PurchaseItem(
      productName: '',
      variantName: 'Portland Cement 40kg',
      sku: '',
      quantity: 20,
      receivedQuantity: 0,
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
  int purchaseCalls = 0;

  @override
  Future<List<Supplier>> fetchSuppliers() async {
    supplierCalls++;
    final failure = this.failure;
    if (failure != null) throw SupplierServiceException(failure);
    return suppliers;
  }

  @override
  Future<List<PurchaseOrder>> fetchPurchaseOrders() async {
    purchaseCalls++;
    final failure = this.failure;
    if (failure != null) throw SupplierServiceException(failure);
    return purchases;
  }

  // Phase 4 Task 4 writes. The stub APPLIES them, so a reload after a write shows
  // the change — which is exactly the property the local `_activeOverrides` map
  // failed: it survived a tab switch and died on a reload.
  final List<Map<String, dynamic>> createdSuppliers = [];
  final List<({int id, Map<String, dynamic> body})> patchedSuppliers = [];
  String? writeError;

  @override
  Future<int> createSupplier(Map<String, dynamic> body) async {
    final error = writeError;
    if (error != null) throw SupplierServiceException(error);
    createdSuppliers.add(body);
    final created = Supplier(
      id: 100 + createdSuppliers.length,
      companyName: body['company_name'] as String,
      contactPerson: (body['contact_person'] as String?) ?? '',
      phone: (body['phone'] as String?) ?? '',
      email: (body['email'] as String?) ?? '',
      address: (body['address'] as String?) ?? '',
    );
    suppliers = [...suppliers, created];
    return created.id;
  }

  @override
  Future<void> patchSupplier(int id, Map<String, dynamic> body) async {
    final error = writeError;
    if (error != null) throw SupplierServiceException(error);
    patchedSuppliers.add((id: id, body: body));
    suppliers = [
      for (final supplier in suppliers)
        supplier.id == id
            ? supplier.copyWith(
                isActive: body['is_active'] as bool?,
                companyName: body['company_name'] as String?,
              )
            : supplier,
    ];
  }

  final List<int> placedOrders = [];
  final List<int> cancelledOrders = [];
  final List<Map<String, dynamic>> createdOrders = [];

  @override
  Future<int> createPurchaseOrder(PurchaseOrderDraft draft) async {
    final error = writeError;
    if (error != null) throw SupplierServiceException(error);
    createdOrders.add(draft.toJson());
    return 77;
  }

  @override
  Future<void> placePurchaseOrder(int id) async {
    final error = writeError;
    if (error != null) throw SupplierServiceException(error);
    placedOrders.add(id);
  }

  @override
  Future<void> cancelPurchaseOrder(int id) async {
    final error = writeError;
    if (error != null) throw SupplierServiceException(error);
    cancelledOrders.add(id);
  }
}

Widget _app(Widget page, SupplierRepository repository) => MultiProvider(
  providers: [
    ChangeNotifierProvider<AuthViewmodel>(
      create: (_) => AuthViewmodel(AuthRepository(AuthService())),
    ),
    ChangeNotifierProvider<SuppliersPurchasesViewmodel>(
      create: (_) => SuppliersPurchasesViewmodel(repository: repository),
    ),
  ],
  child: MaterialApp(home: page),
);

void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('SuppliersPurchasesViewmodel', () {
    test(
      'load joins each PO\'s supplier name from the loaded suppliers',
      () async {
        final repository = _StubSupplierRepository(
          suppliers: [
            _supplier(id: 7, companyName: 'Bohol Cement Traders'),
            _supplier(id: 9, companyName: 'Cebu Steel Works'),
          ],
          purchases: [
            _purchase(id: 41, supplierId: 9, status: PurchaseStatus.ordered),
            _purchase(id: 40, supplierId: 7, status: PurchaseStatus.complete),
          ],
        );
        final viewmodel = SuppliersPurchasesViewmodel(repository: repository);

        await viewmodel.load();

        expect(viewmodel.loadError, isNull);
        expect(viewmodel.isLoading, isFalse);
        expect(viewmodel.suppliers.map((s) => s.companyName), [
          'Bohol Cement Traders',
          'Cebu Steel Works',
        ]);
        expect(viewmodel.purchases.map((p) => p.supplierName), [
          'Cebu Steel Works',
          'Bohol Cement Traders',
        ]);
      },
    );

    test('a failure is reported and the lists stay empty', () async {
      final repository = _StubSupplierRepository()
        ..failure = 'Cannot connect to the BuildPro server.';
      final viewmodel = SuppliersPurchasesViewmodel(repository: repository);

      await viewmodel.load();

      expect(viewmodel.loadError, 'Cannot connect to the BuildPro server.');
      expect(viewmodel.isLoading, isFalse);
      expect(viewmodel.suppliers, isEmpty);
      expect(viewmodel.purchases, isEmpty);
    });

    test(
      'a PO whose supplier is not in the list keeps an empty name',
      () async {
        final repository = _StubSupplierRepository(
          suppliers: [_supplier(id: 7, companyName: 'Bohol Cement Traders')],
          purchases: [
            _purchase(id: 42, supplierId: 99, status: PurchaseStatus.draft),
          ],
        );
        final viewmodel = SuppliersPurchasesViewmodel(repository: repository);

        await viewmodel.load();

        expect(viewmodel.purchases.single.supplierName, '');
      },
    );

    test('a toggle PATCHes is_active and SURVIVES a reload', () async {
      final repository = _StubSupplierRepository(
        suppliers: [_supplier(id: 7, companyName: 'Bohol Cement Traders')],
      );
      final viewmodel = SuppliersPurchasesViewmodel(repository: repository);
      await viewmodel.load();

      final error = await viewmodel.toggleSupplier(viewmodel.suppliers.single);

      expect(error, isNull);
      expect(repository.patchedSuppliers.single.id, 7);
      expect(repository.patchedSuppliers.single.body, {'is_active': false});
      expect(viewmodel.suppliers.single.isActive, isFalse);
      expect(viewmodel.activeSuppliers, 0);

      // The whole point: a reload re-reads the server, and the flag is still off.
      // `_activeOverrides` existed because this used to revert.
      await viewmodel.load();
      expect(viewmodel.suppliers.single.isActive, isFalse);
      expect(viewmodel.activeSuppliers, 0);
    });

    test('a refused toggle reports the message and changes nothing', () async {
      final repository = _StubSupplierRepository(
        suppliers: [_supplier(id: 7, companyName: 'Bohol Cement Traders')],
      )..writeError = 'No permission to change suppliers.';
      final viewmodel = SuppliersPurchasesViewmodel(repository: repository);
      await viewmodel.load();

      final error = await viewmodel.toggleSupplier(viewmodel.suppliers.single);

      expect(error, 'No permission to change suppliers.');
      expect(viewmodel.suppliers.single.isActive, isTrue);
    });

    test('saveSupplier creates with id 0 and PATCHes with a real id', () async {
      final repository = _StubSupplierRepository();
      final viewmodel = SuppliersPurchasesViewmodel(repository: repository);
      await viewmodel.load();

      await viewmodel.saveSupplier(
        _supplier(id: 0, companyName: 'New Trader', contactPerson: 'Ana'),
      );
      expect(repository.createdSuppliers.single['company_name'], 'New Trader');
      expect(viewmodel.suppliers.single.companyName, 'New Trader');

      await viewmodel.saveSupplier(
        viewmodel.suppliers.single.copyWith(companyName: 'Renamed Trader'),
      );
      expect(
        repository.patchedSuppliers.single.body['company_name'],
        'Renamed Trader',
      );
      expect(viewmodel.suppliers.single.companyName, 'Renamed Trader');
    });
  });

  group('SuppliersPage', () {
    testWidgets('loads on open and lists the live suppliers', (tester) async {
      _sizeUp(tester);
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
          _supplier(
            id: 9,
            companyName: 'Cebu Steel Works',
            contactPerson: 'Dan Uy',
            phone: '0918 000 2222',
            email: 'sales@cebusteel.ph',
            address: 'Mandaue City',
          ),
        ],
      );
      await tester.pumpWidget(_app(const SuppliersPage(), repository));
      await tester.pumpAndSettle();

      expect(repository.supplierCalls, 1);
      expect(find.text('Bohol Cement Traders'), findsOneWidget);
      expect(find.text('Cebu Steel Works'), findsOneWidget);
      // The deleted fixtures must not survive anywhere on the screen.
      expect(find.text('Philcement Trading'), findsNothing);
      expect(find.text('Neltex Distribution Cebu'), findsNothing);
    });

    testWidgets('Add supplier saves through the server, not to a local list', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _StubSupplierRepository();
      await tester.pumpWidget(_app(const SuppliersPage(), repository));
      await tester.pumpAndSettle();

      // Phase 4 Task 4 brought this control BACK: in Phase 1 it was removed
      // because the dialog's Save could only have mutated a local list. It now
      // POSTs and reloads, so it exists and it works.
      await tester.tap(find.text('Add supplier'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Company Name'),
        'Tagbilaran Hardware',
      );
      await tester.tap(find.text('Save Supplier'));
      await tester.pumpAndSettle();

      expect(
        repository.createdSuppliers.single['company_name'],
        'Tagbilaran Hardware',
      );
      // The reload is what makes it survive closing the screen.
      expect(repository.supplierCalls, greaterThan(1));
      expect(find.text('Tagbilaran Hardware'), findsOneWidget);
    });

    testWidgets('a failed load shows the error with a working retry', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _StubSupplierRepository()
        ..failure = 'Cannot connect to the BuildPro server.';
      await tester.pumpWidget(_app(const SuppliersPage(), repository));
      await tester.pumpAndSettle();

      expect(find.byType(LiveLoadErrorBanner), findsOneWidget);
      expect(
        find.text('Cannot connect to the BuildPro server.'),
        findsOneWidget,
      );

      repository
        ..failure = null
        ..suppliers = [_supplier(id: 7, companyName: 'Bohol Cement Traders')];
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(repository.supplierCalls, 2);
      expect(find.byType(LiveLoadErrorBanner), findsNothing);
      expect(find.text('Bohol Cement Traders'), findsOneWidget);
    });
  });

  group('PurchasesPage', () {
    testWidgets('lists live POs with the joined supplier name', (tester) async {
      _sizeUp(tester);
      final repository = _StubSupplierRepository(
        suppliers: [_supplier(id: 9, companyName: 'Cebu Steel Works')],
        purchases: [
          _purchase(id: 41, supplierId: 9, status: PurchaseStatus.ordered),
        ],
      );
      await tester.pumpWidget(_app(const PurchasesPage(), repository));
      await tester.pumpAndSettle();

      expect(repository.purchaseCalls, 1);
      expect(find.text('PO-41'), findsOneWidget);
      expect(find.text('Cebu Steel Works'), findsOneWidget);
      // Deleted fixtures.
      expect(find.text('PO-1008'), findsNothing);
    });

    testWidgets('the mock Creating Purchase Order control is gone', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(const PurchasesPage(), _StubSupplierRepository()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create Purchase Order'), findsNothing);
    });

    testWidgets('the status filter still narrows the live list', (
      tester,
    ) async {
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

      expect(find.text('PO-41'), findsOneWidget);
      expect(find.text('PO-40'), findsOneWidget);

      await tester.tap(find.text('All statuses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Complete').last);
      await tester.pumpAndSettle();

      expect(find.text('PO-41'), findsNothing);
      expect(find.text('PO-40'), findsOneWidget);
    });

    testWidgets('a failed load shows the error with a working retry', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _StubSupplierRepository()
        ..failure = 'The purchase orders could not be loaded.';
      await tester.pumpWidget(_app(const PurchasesPage(), repository));
      await tester.pumpAndSettle();

      expect(find.byType(LiveLoadErrorBanner), findsOneWidget);
      expect(
        find.text('The purchase orders could not be loaded.'),
        findsOneWidget,
      );

      repository.failure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.byType(LiveLoadErrorBanner), findsNothing);
      expect(
        find.text('No purchase orders match these filters.'),
        findsOneWidget,
      );
    });
  });

  // `POItemSerializer` sends `variant_name` only — no product name, no SKU. A
  // live PO line therefore arrives with those two strings empty, and the details
  // dialog must not render that emptiness as " — Portland Cement 40kg" or a
  // leading " · " in the subtitle. The variant name alone is the honest label.
  group('PurchasesDetailsDialog', () {
    testWidgets('a live PO line without product name or SKU renders cleanly', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: PurchasesDetailsDialog(
            order: _purchase(
              id: 41,
              supplierId: 9,
              status: PurchaseStatus.ordered,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Portland Cement 40kg'), findsOneWidget);
      expect(find.text(' — Portland Cement 40kg'), findsNothing);
      expect(find.textContaining('· ·'), findsNothing);
    });
  });
}
