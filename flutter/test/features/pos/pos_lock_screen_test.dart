import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/controllers/pos_lock_settings_controller.dart';
import 'package:client/features/pos/controllers/pos_till_settings_controller.dart';
import 'package:client/features/pos/views/pos_settings_page.dart';
import 'package:client/features/pos/widgets/pos_lock_screen_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget buildShell({
    required Future<String?> Function(String password) onVerifyPassword,
    PosLockSettingsController? lockSettings,
  }) {
    SharedPreferences.setMockInitialValues({});
    return ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 800)),
          child: DashboardShell(
            title: 'New transaction',
            subtitle: 'Till #1',
            selectedNavigationIndex: 0,
            navigationItems: const [
              DashboardNavigationItem('New transaction', Icons.point_of_sale),
              DashboardNavigationItem(
                'Transaction history',
                Icons.receipt_long,
              ),
            ],
            loadMarkers: () async => const {},
            onVerifyUnlockPassword: onVerifyPassword,
            lockSettings: lockSettings,
            child: const Center(child: Text('POS Register Content')),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'cashier header lock button opens blurred lock screen and unlocks on valid password',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildShell(
          onVerifyPassword: (password) async {
            return password == 'cashier123' ? null : 'Incorrect password.';
          },
        ),
      );
      await tester.pumpAndSettle();

      final lockButton = find.byKey(const ValueKey('pos-header-lock-button'));
      expect(lockButton, findsOneWidget);
      expect(find.byType(PosLockScreenOverlay), findsNothing);

      // Tap lock icon in header.
      await tester.tap(lockButton);
      await tester.pumpAndSettle();

      expect(find.byType(PosLockScreenOverlay), findsOneWidget);
      expect(find.byType(BackdropFilter), findsWidgets);
      expect(find.text('Screen Locked'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('pos-lock-password-field')),
        findsOneWidget,
      );

      // Wrong password keeps screen locked and displays error.
      await tester.enterText(
        find.byKey(const ValueKey('pos-lock-password-field')),
        'wrong-pass',
      );
      await tester.tap(find.byKey(const ValueKey('pos-lock-unlock-button')));
      await tester.pumpAndSettle();

      expect(find.byType(PosLockScreenOverlay), findsOneWidget);
      expect(find.text('Incorrect password.'), findsOneWidget);

      // Correct password unlocks and reveals the POS workspace.
      await tester.enterText(
        find.byKey(const ValueKey('pos-lock-password-field')),
        'cashier123',
      );
      await tester.tap(find.byKey(const ValueKey('pos-lock-unlock-button')));
      await tester.pumpAndSettle();

      expect(find.byType(PosLockScreenOverlay), findsNothing);
      expect(find.text('POS Register Content'), findsOneWidget);
    },
  );

  testWidgets(
    'POS Settings exposes automatic lock dropdown with 5m, 30m, 1h, 2h, 3h options',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final controller = PosLockSettingsController();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: AuthViewmodel(AuthRepository(AuthService())),
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1280, 800)),
              child: PosSettingsPage(lockSettings: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('pos-settings-menu-security')),
      );
      await tester.pumpAndSettle();

      final dropdown = find.byKey(const ValueKey('pos-auto-lock-dropdown'));
      expect(dropdown, findsOneWidget);

      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      expect(find.text('5 minutes'), findsWidgets);
      expect(find.text('30 minutes'), findsWidgets);
      expect(find.text('1 hour'), findsWidgets);
      expect(find.text('2 hours'), findsWidgets);
      expect(find.text('3 hours'), findsWidgets);

      await tester.tap(find.text('30 minutes').last);
      await tester.pumpAndSettle();

      expect(controller.option, PosAutoLockOption.thirtyMinutes);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(PosLockSettingsController.prefsKey), 30);
    },
  );

  testWidgets(
    'DashboardShell automatically locks after configured inactivity duration',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = PosLockSettingsController();

      await tester.pumpWidget(
        buildShell(
          lockSettings: controller,
          onVerifyPassword: (_) async => null,
        ),
      );
      await tester.pumpAndSettle();

      await controller.setOption(PosAutoLockOption.fiveMinutes);
      await tester.pump();

      // Advance 4 minutes -> still unlocked.
      await tester.pump(const Duration(minutes: 4));
      expect(find.byType(PosLockScreenOverlay), findsNothing);

      // User activity resets the 5-minute inactivity timer.
      await tester.tap(find.text('POS Register Content'));
      await tester.pump(const Duration(minutes: 4));
      expect(find.byType(PosLockScreenOverlay), findsNothing);

      // Reaching 5 full minutes of inactivity triggers the lock screen.
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      expect(find.byType(PosLockScreenOverlay), findsOneWidget);
    },
  );

  testWidgets(
    'POS Settings Checkout & till and Security switches persist preferences',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final lockController = PosLockSettingsController();
      final tillController = PosTillSettingsController();

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: AuthViewmodel(AuthRepository(AuthService())),
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(1280, 800)),
              child: PosSettingsPage(
                lockSettings: lockController,
                tillSettings: tillController,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open Checkout & till section.
      await tester.tap(
        find.byKey(const ValueKey('pos-settings-menu-checkoutAndRegister')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('pos-auto-print-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Always print automatically').last);
      await tester.pumpAndSettle();
      expect(tillController.autoPrintMode, PosAutoPrintMode.always);

      await tester.tap(
        find.byKey(const ValueKey('pos-open-cash-drawer-switch')),
      );
      await tester.pumpAndSettle();
      expect(tillController.autoOpenCashDrawer, isTrue);

      final soundSwitch = find.byKey(
        const ValueKey('pos-sound-feedback-switch'),
      );
      await tester.ensureVisible(soundSwitch);
      await tester.pumpAndSettle();
      await tester.tap(soundSwitch);
      await tester.pumpAndSettle();
      expect(tillController.soundFeedback, isFalse);

      // Open Security & lock section and toggle lock-after-sale.
      final securityMenu = find.byKey(
        const ValueKey('pos-settings-menu-security'),
      );
      await tester.ensureVisible(securityMenu);
      await tester.pumpAndSettle();
      await tester.tap(securityMenu);
      await tester.pumpAndSettle();

      final lockAfterSaleSwitch = find.byKey(
        const ValueKey('pos-lock-after-sale-switch'),
      );
      await tester.ensureVisible(lockAfterSaleSwitch);
      await tester.pumpAndSettle();
      await tester.tap(lockAfterSaleSwitch);
      await tester.pumpAndSettle();
      expect(lockController.lockAfterSale, isTrue);

      // Notifying sale completion triggers lock screen when lockAfterSale is on.
      lockController.notifySaleCompleted();
      await tester.pumpAndSettle();
      expect(find.byType(PosLockScreenOverlay), findsOneWidget);
    },
  );
}
