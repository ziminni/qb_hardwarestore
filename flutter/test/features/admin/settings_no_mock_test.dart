// Decision D-03 (admin-workflow): the last two `AdminMockData` consumers were
// the Settings screens. Mock data is fine in a prototype; a store's own name and
// contact details sitting in a "mock data" bag is not, because the bag reads as
// fake and these three values are the only real ones the store actually has.
//
// These tests pin:
//   * the admin Settings screen shows the inlined store constants,
//   * the stocker Settings screen shows the SAME constants (one store, one name)
//     and stays read-only with no Save button,
//   * nothing renders the old `AdminMockData` literals — the file is deleted in
//     this phase, so a resurrected literal has to come from somewhere new.
//     (The store's trading name is checked in the FORM FIELDS only: the sidebar
//     brand renders 'Queen Builders' as chrome, which is not mock data.)

import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/admin/views/settings_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

const _storeName = 'QB Hardware & Construction Supplies';
const _storeEmail = 'contact@qbhardware.com';
const _storePhone = '+63 912 345 6789';

Widget _app(Widget page) => ChangeNotifierProvider<AuthViewmodel>(
  create: (_) => AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: page),
);

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(page));
  await tester.pumpAndSettle();
}

List<String?> _fieldValues(WidgetTester tester) => tester
    .widgetList<TextFormField>(find.byType(TextFormField))
    .map((field) => field.initialValue)
    .toList();

void main() {
  group('admin SettingsPage', () {
    testWidgets('shows the inlined store constants', (tester) async {
      await _pump(tester, const SettingsPage());

      expect(_fieldValues(tester), [_storeName, _storeEmail, _storePhone]);
    });

    testWidgets('no AdminMockData literal survives in the fields', (
      tester,
    ) async {
      await _pump(tester, const SettingsPage());

      // Scoped to the fields on purpose: the sidebar brand legitimately renders
      // the shop's trading name (`SystemBrand`), so a bare `find.text('Queen
      // Builders')` would flag the chrome rather than the settings data.
      expect(_fieldValues(tester), isNot(contains('Queen Builders')));
      expect(
        _fieldValues(tester),
        isNot(contains('admin@queenbuilders.local')),
      );
      expect(_fieldValues(tester), isNot(contains('+63 900 000 0000')));
      expect(find.text('admin@queenbuilders.local'), findsNothing);
      expect(find.text('+63 900 000 0000'), findsNothing);
    });
  });

  group('stocker InventorySettingsPage', () {
    testWidgets('shows the same constants, read-only, with no Save', (
      tester,
    ) async {
      await _pump(tester, const InventorySettingsPage());

      expect(_fieldValues(tester), [_storeName, _storeEmail, _storePhone]);
      expect(
        tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .every((field) => field.enabled == false),
        isTrue,
        reason: 'a stocker cannot change store settings',
      );
      expect(find.text('Save settings'), findsNothing);
      expect(find.text('admin@queenbuilders.local'), findsNothing);
      expect(find.text('+63 900 000 0000'), findsNothing);
    });
  });
}
