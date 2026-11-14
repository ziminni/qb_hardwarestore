// Phase 4 Task F3a: the Admin Settings page edits the server-owned store
// settings (VAT on/rate, discount cap). The static store-information card stays
// as it was: those three facts still have no endpoint.
//
// What this pins:
//   * the page loads and shows what the SERVER says,
//   * the VAT rate field only exists while VAT is registered,
//   * bad input never reaches the API (0 to 100, at most 2 decimal places),
//   * Save shows progress, then a success snackbar,
//   * a server refusal appears in an ErrorBanner with the server's detail,
//   * a non-admin sees the values and no way to change them.

import 'package:client/data/models/role.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/store_settings_service.dart';
import 'package:client/features/admin/viewmodels/store_settings_viewmodel.dart';
import 'package:client/features/admin/views/settings_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubService extends StoreSettingsService {
  _StubService({this.stored = _stored, this.loadFailure, this.saveFailure});

  StoreSettings stored;
  String? loadFailure;
  StoreSettingsException? saveFailure;
  final List<StoreSettings> saved = [];
  int loads = 0;

  @override
  Future<StoreSettings> fetch() async {
    loads++;
    final loadFailure = this.loadFailure;
    if (loadFailure != null) throw StoreSettingsException(loadFailure);
    return stored;
  }

  @override
  Future<StoreSettings> save(StoreSettings settings) async {
    final saveFailure = this.saveFailure;
    if (saveFailure != null) throw saveFailure;
    saved.add(settings);
    stored = settings;
    return settings;
  }
}

const _stored = StoreSettings(
  vatRegistered: true,
  vatRate: 12,
  discountCapPercent: 10,
);

Future<void> _pump(
  WidgetTester tester,
  _StubService service, {
  String roleCode = 'admin',
  String roleLabel = 'Admin',
}) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = AuthViewmodel(AuthRepository(AuthService()))
    ..user = User(
      id: 1,
      username: 'admin',
      email: 'admin@example.com',
      fullName: 'Admin User',
      role: Role(id: 1, name: roleCode, displayName: roleLabel),
      isActive: true,
    );

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(
        home: SettingsPage(viewmodel: StoreSettingsViewmodel(service: service)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

Future<void> _type(WidgetTester tester, String label, String value) async {
  await tester.enterText(_field(label), value);
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Save settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the server values and keeps the store card', (
    tester,
  ) async {
    final service = _StubService();
    await _pump(tester, service);

    expect(service.loads, 1);
    expect(find.text('Sales settings'), findsOneWidget);
    expect(find.text('12.00'), findsOneWidget);
    expect(find.text('10.00'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(
      tester.widget<Switch>(find.byType(Switch)).value,
      isTrue,
      reason: 'VAT registered comes from the server, not a local default',
    );

    // The note that keeps a reader from adding VAT twice.
    expect(
      find.text('Prices on the shelf already include VAT.'),
      findsOneWidget,
    );

    // Card A6 content is untouched: no store-details endpoint exists.
    expect(find.text('Store information'), findsOneWidget);
    expect(find.text('QB Hardware & Construction Supplies'), findsOneWidget);
    expect(
      find.text('Editing store details is not available yet.'),
      findsOneWidget,
    );
  });

  testWidgets('the VAT rate field only exists while VAT is registered', (
    tester,
  ) async {
    final service = _StubService(
      stored: const StoreSettings(
        vatRegistered: false,
        vatRate: 0,
        discountCapPercent: 10,
      ),
    );
    await _pump(tester, service);

    expect(_field('VAT rate (%)'), findsNothing);
    expect(_field('Discount cap (%)'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(_field('VAT rate (%)'), findsOneWidget);
  });

  testWidgets('Save sends what was typed', (tester) async {
    final service = _StubService();
    await _pump(tester, service);

    await _type(tester, 'Discount cap (%)', '15.50');
    await _save(tester);

    expect(service.saved.single.discountCapPercent, 15.5);
    expect(service.saved.single.vatRate, 12);
    expect(service.saved.single.vatRegistered, isTrue);
    expect(find.text('Store settings saved.'), findsOneWidget);
  });

  testWidgets('an out-of-range percent never reaches the server', (
    tester,
  ) async {
    final service = _StubService();
    await _pump(tester, service);

    await _type(tester, 'Discount cap (%)', '150');
    await _save(tester);

    expect(service.saved, isEmpty);
    expect(find.text('Enter a number from 0 to 100.'), findsOneWidget);
    expect(find.text('Store settings saved.'), findsNothing);
  });

  testWidgets('three decimal places are refused before the request', (
    tester,
  ) async {
    final service = _StubService();
    await _pump(tester, service);

    await _type(tester, 'VAT rate (%)', '12.345');
    await _save(tester);

    expect(service.saved, isEmpty);
    expect(find.text('Use at most 2 decimal places.'), findsOneWidget);
  });

  // The server is the trust boundary (phase rules). A 403 from a Store Manager
  // who reached the PATCH, or a 400 field refusal, must appear in the page's own
  // banner with the sentence the server sent.
  testWidgets('a server refusal shows in the ErrorBanner', (tester) async {
    final service = _StubService(
      saveFailure: const StoreSettingsException(
        'Only an Admin may change store settings.',
        isForbidden: true,
      ),
    );
    await _pump(tester, service);

    await _save(tester);

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(
      find.text('Only an Admin may change store settings.'),
      findsOneWidget,
    );
    expect(find.text('Store settings saved.'), findsNothing);
  });

  testWidgets('a failed load names itself and offers a retry', (tester) async {
    final service = _StubService(
      loadFailure: 'The store settings could not be loaded.',
    );
    await _pump(tester, service);

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(
      find.text('The store settings could not be loaded.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('a non-admin reads the values and cannot change them', (
    tester,
  ) async {
    final service = _StubService();
    await _pump(tester, service, roleCode: 'sales', roleLabel: 'Store Manager');

    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Save settings'), findsNothing);
    expect(find.text('VAT registered'), findsOneWidget);
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('12.00%'), findsOneWidget);
    expect(find.text('10.00%'), findsOneWidget);
    expect(
      find.text('Only an Admin can change these settings.'),
      findsOneWidget,
    );
  });
}
