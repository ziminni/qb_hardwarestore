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
    // Card A6 (UI refresh): the three store facts are now a read-only
    // "Store information" card instead of three disabled text fields. A
    // disabled field looks like a form waiting to be enabled, and there is no
    // settings endpoint to enable it (D-03), so the values are shown, not
    // implied to be editable. The values themselves are unchanged (D10).
    testWidgets('shows the store constants in a read-only card', (
      tester,
    ) async {
      await _pump(tester, const SettingsPage());

      expect(find.text('Store information'), findsOneWidget);
      expect(find.text(_storeName), findsOneWidget);
      expect(find.text(_storeEmail), findsOneWidget);
      expect(find.text(_storePhone), findsOneWidget);
      expect(
        find.text('Editing store details is not available yet.'),
        findsOneWidget,
      );
      expect(
        find.byType(TextFormField),
        findsNothing,
        reason: 'no field may imply these values can be edited',
      );
      expect(find.text('Save settings'), findsNothing);
    });

    testWidgets('no AdminMockData literal survives', (tester) async {
      await _pump(tester, const SettingsPage());

      // The sidebar brand legitimately renders the shop's trading name
      // (`SystemBrand`), so only the settings data is checked here.
      expect(find.text('admin@queenbuilders.local'), findsNothing);
      expect(find.text('+63 900 000 0000'), findsNothing);
      expect(find.text(_storeName), findsOneWidget);
    });
  });

  group('stocker InventorySettingsPage', () {
    // Card K10 (UI refresh): the stocker's Settings screen now shows the SAME
    // read-only "Store information" card as the admin one (card A6), instead of
    // three disabled fields that looked like a form waiting to be enabled.
    testWidgets('shows the same constants, read-only, with no Save', (
      tester,
    ) async {
      await _pump(tester, const InventorySettingsPage());

      expect(find.text('Store information'), findsOneWidget);
      // Same three literals as the admin card: one store, one name (D-03, D10).
      // `_fieldValues` would be empty here by design, so the values are read as
      // text rather than from fields that no longer exist.
      expect(_fieldValues(tester), isEmpty);
      expect(find.text(_storeName), findsOneWidget);
      expect(find.text(_storeEmail), findsOneWidget);
      expect(find.text(_storePhone), findsOneWidget);
      expect(
        find.byType(TextFormField),
        findsNothing,
        reason: 'a stocker cannot change store settings',
      );
      expect(find.text('Save settings'), findsNothing);
      expect(find.text('admin@queenbuilders.local'), findsNothing);
      expect(find.text('+63 900 000 0000'), findsNothing);
    });
  });
}
