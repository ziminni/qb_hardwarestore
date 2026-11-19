// The till's Settings tab (owner 2026-11-18): the cashier, not the Admin,
// chooses the receipt printer on the counter computer.

import 'dart:typed_data';

import 'package:client/core/printing/raw_printer.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/store_settings_service.dart';
import 'package:client/features/admin/viewmodels/store_settings_viewmodel.dart';
import 'package:client/features/admin/views/settings_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/views/pos_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/offline_catalogue_lists.dart';

class _FakeRaw implements RawPrinter {
  @override
  Future<List<RawPrinterInfo>> printers() async => const [
    RawPrinterInfo(id: 'GEZHI_micro_printer', name: 'GEZHI micro-printer'),
  ];

  @override
  Future<void> send(
    String printerId,
    Uint8List bytes, {
    required String job,
  }) async {}
}

class _StubSettingsService extends StoreSettingsService {
  @override
  Future<StoreSettings> fetch() async => StoreSettings.defaults;
}

void _bigWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the till Settings tab lists this computer\'s printers', (
    tester,
  ) async {
    _bigWindow(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>(
        create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        child: MaterialApp(home: PosSettingsPage(raw: _FakeRaw())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GEZHI micro-printer'), findsOneWidget);
    expect(find.text('Print test receipt'), findsOneWidget);
  });

  testWidgets('the Admin Settings offers no receipt printer to change', (
    tester,
  ) async {
    _bigWindow(tester);
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

    expect(find.textContaining('Receipt printer'), findsNothing);
    expect(find.text('Print test receipt'), findsNothing);
  });
}
