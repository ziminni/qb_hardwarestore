// Owner 2026-11-18: Admin → Settings is organised with side tabs on the left,
// like GitHub's settings: one section open at a time.

import 'package:client/data/models/store_settings.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/store_settings_service.dart';
import 'package:client/features/admin/viewmodels/store_settings_viewmodel.dart';
import 'package:client/features/admin/views/settings_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/offline_catalogue_lists.dart';

class _StubSettingsService extends StoreSettingsService {
  @override
  Future<StoreSettings> fetch() async => StoreSettings.defaults;
}

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>(
      create: (_) => AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        home: SettingsPage(
          viewmodel: StoreSettingsViewmodel(service: _StubSettingsService()),
          catalogueLists: OfflineCatalogueLists(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _menu(String name) => find.byKey(ValueKey('settings-menu-$name'));

Finder _section(String name) => find.byKey(ValueKey('settings-section-$name'));

Future<void> _open(WidgetTester tester, String name) async {
  await tester.ensureVisible(_menu(name));
  await tester.tap(_menu(name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a wide window puts the menu on the left, grouped, in order', (
    tester,
  ) async {
    await _pump(tester, const Size(1600, 1200));

    final menu = tester.getRect(find.byKey(const ValueKey('settings-menu')));
    final section = tester.getRect(_section('sales'));
    expect(menu.right, lessThan(section.left), reason: 'menu left of content');

    final tops = [
      for (final name in ['sales', 'store', 'categories', 'suppliers'])
        tester.getTopLeft(_menu(name)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.text('Store'), findsOneWidget);
    expect(find.text('Catalogue'), findsOneWidget);
  });

  testWidgets('one section is open at a time', (tester) async {
    await _pump(tester, const Size(1600, 1200));
    expect(_section('sales'), findsOneWidget);

    await _open(tester, 'suppliers');

    expect(_section('suppliers'), findsOneWidget);
    expect(_section('sales'), findsNothing);
    expect(find.text('Save settings'), findsNothing);
    expect(find.byKey(const ValueKey('add-supplier')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-category')), findsNothing);
    // The side tab replaces the panel's own Categories / Suppliers tabs.
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('Categories shows only the category list', (tester) async {
    await _pump(tester, const Size(1600, 1200));

    await _open(tester, 'categories');

    expect(find.byKey(const ValueKey('add-category')), findsOneWidget);
    expect(find.byKey(const ValueKey('add-supplier')), findsNothing);
  });

  testWidgets('a narrow window turns the menu into a row above the section', (
    tester,
  ) async {
    await _pump(tester, const Size(700, 1400));

    final menu = tester.getRect(find.byKey(const ValueKey('settings-menu')));
    final section = tester.getRect(_section('sales'));
    expect(menu.bottom, lessThanOrEqualTo(section.top));
    expect(tester.takeException(), isNull);

    await _open(tester, 'store');
    expect(_section('store'), findsOneWidget);
  });
}
