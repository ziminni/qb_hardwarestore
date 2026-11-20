import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/controllers/inventory_settings_controller.dart';
import 'package:client/features/inventory/views/inventory_settings_page.dart';
import 'package:client/features/pos/controllers/pos_lock_settings_controller.dart';
import 'package:client/features/pos/widgets/pos_lock_screen_overlay.dart';
import 'package:client/features/sales/controllers/sales_settings_controller.dart';
import 'package:client/features/sales/views/sales_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Widget wrapPage(Widget page) {
    return ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(1280, 900)),
          child: page,
        ),
      ),
    );
  }

  testWidgets(
    'Store Manager Settings saves reports, oversight, and auto-lock preferences and has header lock',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final controller = SalesSettingsController();

      await tester.pumpWidget(
        wrapPage(SalesSettingsPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Open Reports & oversight section.
      await tester.tap(
        find.byKey(const ValueKey('sales-settings-menu-reports')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('sales-default-range-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('This month').last);
      await tester.pumpAndSettle();
      expect(controller.defaultReportRange, SalesDefaultReportRange.thisMonth);

      await tester.tap(
        find.byKey(const ValueKey('sales-default-export-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('CSV (.csv)').last);
      await tester.pumpAndSettle();
      expect(controller.defaultExportFormat, SalesDefaultExportFormat.csv);

      final maskSwitch = find.byKey(const ValueKey('sales-mask-cost-switch'));
      await tester.ensureVisible(maskSwitch);
      await tester.tap(maskSwitch);
      await tester.pumpAndSettle();
      expect(controller.maskCostAndMargin, isTrue);

      // Open Security & lock section.
      final securityMenu = find.byKey(
        const ValueKey('sales-settings-menu-security'),
      );
      await tester.ensureVisible(securityMenu);
      await tester.tap(securityMenu);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('sales-auto-lock-dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 hour').last);
      await tester.pumpAndSettle();
      expect(controller.autoLockOption, PosAutoLockOption.oneHour);

      // Header lock button opens blurred lock screen.
      await tester.tap(find.byKey(const ValueKey('sales-header-lock-button')));
      await tester.pumpAndSettle();
      expect(find.byType(PosLockScreenOverlay), findsOneWidget);
    },
  );

  testWidgets(
    'Stock Manager Settings saves warehouse, scanner, and auto-lock preferences and has header lock',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      SharedPreferences.setMockInitialValues({});
      final controller = InventorySettingsController();

      await tester.pumpWidget(
        wrapPage(InventorySettingsPage(controller: controller)),
      );
      await tester.pumpAndSettle();

      // Open Stock & receiving section.
      await tester.tap(
        find.byKey(const ValueKey('inventory-settings-menu-warehouse')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('inventory-default-reason-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Physical count').last);
      await tester.pumpAndSettle();
      expect(
        controller.defaultAdjustmentReason,
        InventoryAdjustmentReason.physicalCount,
      );

      final quickCount = find.byKey(
        const ValueKey('inventory-quick-count-dropdown'),
      );
      await tester.ensureVisible(quickCount);
      await tester.tap(quickCount);
      await tester.pumpAndSettle();
      await tester.tap(find.text('+5 units').last);
      await tester.pumpAndSettle();
      expect(controller.quickCountStep, 5);

      final soundSwitch = find.byKey(
        const ValueKey('inventory-sound-feedback-switch'),
      );
      await tester.ensureVisible(soundSwitch);
      await tester.tap(soundSwitch);
      await tester.pumpAndSettle();
      expect(controller.soundFeedback, isFalse);

      // Open Security & lock section.
      final securityMenu = find.byKey(
        const ValueKey('inventory-settings-menu-security'),
      );
      await tester.ensureVisible(securityMenu);
      await tester.tap(securityMenu);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('inventory-auto-lock-dropdown')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('30 minutes').last);
      await tester.pumpAndSettle();
      expect(controller.autoLockOption, PosAutoLockOption.thirtyMinutes);

      // Header lock button opens blurred lock screen.
      await tester.tap(
        find.byKey(const ValueKey('inventory-header-lock-button')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PosLockScreenOverlay), findsOneWidget);
    },
  );
}
