import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/core/theme/theme_settings_controller.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/store_settings_service.dart';
import 'package:client/features/admin/viewmodels/store_settings_viewmodel.dart';
import 'package:client/features/admin/views/settings_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_settings_page.dart';
import 'package:client/features/pos/views/pos_settings_page.dart';
import 'package:client/features/sales/views/sales_settings_page.dart';
import 'package:client/shared/widgets/system_settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/offline_catalogue_lists.dart';

class _StubStoreSettingsService extends StoreSettingsService {
  @override
  Future<StoreSettings> fetch() async => StoreSettings.defaults;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ThemeSettingsController.instance.resetInMemory();
  });

  tearDown(() {
    ThemeSettingsController.instance.resetInMemory();
  });

  test('ThemeSettingsController persists local device choices and reloads', () async {
    final writer = ThemeSettingsController();
    await writer.setAppearance(AppAppearanceMode.obsidianDark);
    await writer.setAccent(AppAccentPreset.blueprintCobalt);
    await writer.setSidebarStyle(AppSidebarStyle.charcoal);
    await writer.setDisplayScale(AppDisplayScale.comfortable);

    final reader = ThemeSettingsController();
    await reader.load();

    expect(reader.settings.appearance, AppAppearanceMode.obsidianDark);
    expect(reader.settings.accent, AppAccentPreset.blueprintCobalt);
    expect(reader.settings.sidebarStyle, AppSidebarStyle.charcoal);
    expect(reader.settings.displayScale, AppDisplayScale.comfortable);

    await reader.reset();
    final afterReset = ThemeSettingsController();
    await afterReset.load();
    expect(afterReset.settings, ThemeSettings.defaults);
  });

  test('every built theme preserves the Cinzel / OpenSans typography split', () {
    for (final appearance in AppAppearanceMode.values) {
      for (final accent in AppAccentPreset.values) {
        final theme = AppTheme.buildTheme(
          ThemeSettings(appearance: appearance, accent: accent),
        );
        expect(theme.textTheme.titleLarge?.fontFamily, AppTextStyles.cinzelFont);
        expect(theme.textTheme.bodyMedium?.fontFamily, AppTextStyles.outfitFont);
        expect(theme.brightness, appearance.isDark ? Brightness.dark : Brightness.light);
      }
    }
  });

  testWidgets('Admin Settings opens System settings and applies local theme live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>(
        create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        child: ListenableBuilder(
          listenable: ThemeSettingsController.instance,
          builder: (context, _) => MaterialApp(
            theme: AppTheme.buildTheme(ThemeSettingsController.instance.settings),
            home: SettingsPage(
              viewmodel: StoreSettingsViewmodel(
                service: _StubStoreSettingsService(),
              ),
              catalogueLists: OfflineCatalogueLists(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Open the new System settings side tab.
    await tester.tap(find.byKey(const ValueKey('settings-menu-system')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-section-system')), findsOneWidget);
    expect(find.byType(SystemSettingsPanel), findsOneWidget);

    // Switch to Obsidian Dark + Blueprint Blue + Comfortable display scale.
    await tester.tap(find.byKey(const ValueKey('theme-appearance-obsidian_dark')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-accent-blueprint_cobalt')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('theme-scale-comfortable')),
    );
    await tester.tap(find.byKey(const ValueKey('theme-scale-comfortable')));
    await tester.pumpAndSettle();

    final current = ThemeSettingsController.instance.settings;
    expect(current.appearance, AppAppearanceMode.obsidianDark);
    expect(current.accent, AppAccentPreset.blueprintCobalt);
    expect(current.displayScale, AppDisplayScale.comfortable);

    // Verify live MaterialApp theme switched to dark + Blueprint Blue accent.
    final scaffoldCtx = tester.element(find.byType(SystemSettingsPanel));
    final palette = AppPalette.of(scaffoldCtx);
    expect(palette.isDark, isTrue);
    expect(palette.accent, AppAccentPreset.blueprintCobalt.accent);

    // Reset restores defaults.
    await tester.ensureVisible(find.byKey(const ValueKey('theme-reset-button')));
    await tester.tap(find.byKey(const ValueKey('theme-reset-button')));
    await tester.pumpAndSettle();

    expect(ThemeSettingsController.instance.settings, ThemeSettings.defaults);
  });

  testWidgets('POS Settings also exposes the local System settings tab', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>(
        create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        child: const MaterialApp(home: PosSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pos-settings-menu-system')));
    await tester.pumpAndSettle();

    expect(find.byType(SystemSettingsPanel), findsOneWidget);
  });

  testWidgets(
    'Stock Manager Settings uses the same grouped side-tab layout',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>(
          create: (_) => AuthViewmodel(AuthRepository(AuthService())),
          child: const MaterialApp(home: InventorySettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      final menu = tester.getRect(
        find.byKey(const ValueKey('inventory-settings-menu')),
      );
      final section = tester.getRect(
        find.byKey(const ValueKey('inventory-settings-section-store')),
      );
      expect(menu.right, lessThan(section.left));

      await tester.tap(
        find.byKey(const ValueKey('inventory-settings-menu-system')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SystemSettingsPanel), findsOneWidget);
    },
  );

  testWidgets(
    'Store Manager Settings uses the same grouped side-tab layout',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>(
          create: (_) => AuthViewmodel(AuthRepository(AuthService())),
          child: const MaterialApp(home: SalesSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      final menu = tester.getRect(
        find.byKey(const ValueKey('sales-settings-menu')),
      );
      final section = tester.getRect(
        find.byKey(const ValueKey('sales-settings-section-store')),
      );
      expect(menu.right, lessThan(section.left));

      await tester.tap(find.byKey(const ValueKey('sales-settings-menu-system')));
      await tester.pumpAndSettle();
      expect(find.byType(SystemSettingsPanel), findsOneWidget);
    },
  );
}
