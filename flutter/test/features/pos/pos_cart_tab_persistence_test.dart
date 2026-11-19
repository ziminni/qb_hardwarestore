import 'package:client/data/models/shift.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/data/services/store_settings_service.dart';
import 'package:client/features/admin/viewmodels/store_settings_viewmodel.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

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

class _StubStoreSettingsService extends StoreSettingsService {
  @override
  Future<StoreSettings> fetch() async => StoreSettings.defaults;
}

class _TabSwitcherHarness extends StatefulWidget {
  const _TabSwitcherHarness({required this.shiftFactory});

  final ShiftViewmodel Function() shiftFactory;

  @override
  State<_TabSwitcherHarness> createState() => _TabSwitcherHarnessState();
}

class _TabSwitcherHarnessState extends State<_TabSwitcherHarness> {
  bool _onTill = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            TextButton(
              key: const ValueKey('switch-to-other-tab'),
              onPressed: () => setState(() => _onTill = false),
              child: const Text('Other tab'),
            ),
            TextButton(
              key: const ValueKey('switch-to-till-tab'),
              onPressed: () => setState(() => _onTill = true),
              child: const Text('Till tab'),
            ),
          ],
        ),
        Expanded(
          child: _onTill
              // Production route constructs `PosTransactionPage()` without an
              // explicit `viewmodel` argument; it must resolve the app-scoped
              // `PosTransactionViewmodel` from Provider so tab switches keep
              // the cashier's cart intact.
              ? PosTransactionPage(
                  key: const ValueKey('till-page'),
                  shiftViewmodel: widget.shiftFactory(),
                )
              : const Scaffold(
                  key: ValueKey('other-page'),
                  body: Center(child: Text('Transaction History')),
                ),
        ),
      ],
    );
  }
}

void main() {
  testWidgets(
    'added materials stay cached across tab switches until removed or cleared',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final inventory = seededInventory();
      final appCart = PosTransactionViewmodel(inventory);
      addTearDown(appCart.dispose);

      final product = appCart.filteredProducts.first;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthViewmodel>(
              create: (_) => AuthViewmodel(AuthRepository(AuthService())),
            ),
            ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
            ChangeNotifierProvider<HeldCartViewmodel>(
              create: (_) => HeldCartViewmodel(),
            ),
            ChangeNotifierProvider<StoreSettingsViewmodel>(
              create: (_) => StoreSettingsViewmodel(
                service: _StubStoreSettingsService(),
              ),
            ),
            ChangeNotifierProvider<PosTransactionViewmodel>.value(
              value: appCart,
            ),
          ],
          child: MaterialApp(
            home: _TabSwitcherHarness(
              shiftFactory: () => ShiftViewmodel(service: _OpenShift()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Add a material from the till product browser (tap product -> confirm dialog).
      await tester.tap(find.text(product.productName).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add to cart'));
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Remove ${product.productName}'),
        findsOneWidget,
        reason: 'the material must appear in the cart right after adding it',
      );

      // Switch away to another tab (disposes PosTransactionPage) and come back.
      await tester.tap(find.byKey(const ValueKey('switch-to-other-tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('other-page')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('switch-to-till-tab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('till-page')), findsOneWidget);

      expect(
        find.byTooltip('Remove ${product.productName}'),
        findsOneWidget,
        reason: 'switching tabs must NOT wipe the materials added to the cart',
      );
      expect(appCart.lines.length, 1);

      // Removing the item clears it and stays cleared across another tab switch.
      await tester.tap(find.byTooltip('Remove ${product.productName}'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove ${product.productName}'), findsNothing);

      // Add again, then verify Clear transaction prompts "Are you sure" first.
      await tester.tap(find.text(product.productName).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add to cart'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove ${product.productName}'), findsOneWidget);

      await tester.tap(find.text('Clear transaction'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Are you sure'),
        findsOneWidget,
        reason: 'Clear transaction must prompt before wiping the cart',
      );

      // Cancelling the prompt keeps the materials in the cart.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Remove ${product.productName}'),
        findsOneWidget,
        reason: 'cancelling Clear transaction must keep the added materials',
      );

      // Confirming Clear removes the materials and stays cleared across tabs.
      await tester.tap(find.text('Clear transaction'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove ${product.productName}'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('switch-to-other-tab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('switch-to-till-tab')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove ${product.productName}'), findsNothing);
    },
  );

  test('resetSession clears cached lines and search query on sign-out', () {
    final inventory = seededInventory();
    final cart = PosTransactionViewmodel(inventory);
    addTearDown(cart.dispose);

    final product = cart.filteredProducts.first;
    expect(cart.addLine(product, 2), isNull);
    cart.setQuery('cement');
    expect(cart.lines, hasLength(1));
    expect(cart.query, 'cement');

    cart.resetSession();

    expect(cart.lines, isEmpty);
    expect(cart.query, isEmpty);
    expect(cart.selectedCustomer, isNull);
  });
}
