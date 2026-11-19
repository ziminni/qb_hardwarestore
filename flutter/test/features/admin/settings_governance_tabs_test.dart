import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/catalogue_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/store_settings_service.dart';
import 'package:client/features/admin/viewmodels/store_settings_viewmodel.dart';
import 'package:client/features/admin/views/settings_page.dart';
import 'package:client/features/admin/widgets/catalogue_masters_panel.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/offline_catalogue_lists.dart';

class _StubSettingsService extends StoreSettingsService {
  @override
  Future<StoreSettings> fetch() async => StoreSettings.defaults;
}

class _InMemoryCatalogueRepository extends CatalogueRepository {
  final List<Brand> _brands = [
    const Brand(id: 1, name: 'Holcim'),
    const Brand(id: 2, name: 'FlowPro'),
  ];
  final List<UnitOfMeasure> _units = [
    const UnitOfMeasure(id: 1, code: 'PC', name: 'Piece', isWhole: true),
    const UnitOfMeasure(id: 2, code: 'KG', name: 'Kilogram', isWhole: false),
  ];

  @override
  Future<List<Brand>> fetchBrands() async => List.of(_brands);

  @override
  Future<List<UnitOfMeasure>> fetchUnits() async => List.of(_units);

  @override
  Future<int> createBrand(String name) async {
    final id = _brands.length + 1;
    _brands.add(Brand(id: id, name: name));
    return id;
  }

  @override
  Future<void> patchBrand(int id, {required String name}) async {
    final idx = _brands.indexWhere((b) => b.id == id);
    if (idx >= 0) _brands[idx] = Brand(id: id, name: name);
  }

  @override
  Future<int> createUnit({required String code, required String name}) async {
    final id = _units.length + 1;
    _units.add(UnitOfMeasure(id: id, code: code, name: name));
    return id;
  }

  @override
  Future<void> patchUnit(int id, {String? code, String? name}) async {
    final idx = _units.indexWhere((u) => u.id == id);
    if (idx >= 0) {
      final old = _units[idx];
      _units[idx] = UnitOfMeasure(
        id: id,
        code: code ?? old.code,
        name: name ?? old.name,
        isWhole: old.isWhole,
      );
    }
  }
}

Future<void> _pumpSettings(
  WidgetTester tester,
  _InMemoryCatalogueRepository repo,
) async {
  tester.view.physicalSize = const Size(1500, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final auth = AuthViewmodel(AuthRepository(AuthService()))
    ..user = const User(
      id: 1,
      username: 'admin',
      email: 'admin@qbhardware.com',
      fullName: 'Ada Min',
      role: Role(id: 1, name: 'admin', displayName: 'Admin'),
      isActive: true,
    );

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: SettingsPage(
          viewmodel: StoreSettingsViewmodel(service: _StubSettingsService()),
          catalogueLists: OfflineCatalogueLists(),
          catalogueMasters: CatalogueMastersViewmodel(repository: repo),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Admin Settings includes Receipts & numbering, Brands, and Units (UOM) tabs',
    (tester) async {
      final repo = _InMemoryCatalogueRepository();
      await _pumpSettings(tester, repo);

      // 1. Receipts & numbering tab
      await tester.tap(find.byKey(const ValueKey('settings-menu-documents')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-section-documents')), findsOneWidget);
      expect(find.text('Document numbering series'), findsOneWidget);
      expect(find.text('OR-001001'), findsOneWidget);
      expect(find.byKey(const ValueKey('receipt-template-preview')), findsOneWidget);

      // Updating the header field updates the live receipt preview.
      await tester.enterText(
        find.widgetWithText(TextField, 'Receipt header title'),
        'QUEEN BUILDERS MAIN BRANCH',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('receipt-template-preview')),
          matching: find.text('QUEEN BUILDERS MAIN BRANCH'),
        ),
        findsOneWidget,
      );

      // 2. Brands tab (live CRUD via repository)
      await tester.tap(find.byKey(const ValueKey('settings-menu-brands')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-section-brands')), findsOneWidget);
      expect(find.text('Holcim'), findsOneWidget);
      expect(find.text('FlowPro'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('add-brand')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Brand name'),
        'Davies',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add brand').last);
      await tester.pumpAndSettle();
      expect(find.text('Davies'), findsOneWidget);

      // 3. Units (UOM) tab (live CRUD via repository + whole/fractional badges)
      await tester.tap(find.byKey(const ValueKey('settings-menu-units')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-section-units')), findsOneWidget);
      expect(find.text('PC'), findsOneWidget);
      expect(find.text('Whole unit'), findsOneWidget);
      expect(find.text('Fractional allowed'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('add-unit')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Unit code'),
        'bag',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Unit name'),
        'Bag',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add unit').last);
      await tester.pumpAndSettle();
      expect(find.text('BAG'), findsOneWidget);
      expect(find.text('Bag'), findsOneWidget);
    },
  );
}
