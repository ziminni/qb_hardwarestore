import 'package:client/app.dart';
import 'package:client/core/config/api_config.dart';
import 'package:client/core/network/api_client.dart';
import 'package:client/core/theme/theme_settings_controller.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/active_area_store.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/admin/viewmodels/store_settings_viewmodel.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A server address saved on this phone beats the build's default.
  await ApiConfig.loadSaved();
  ApiClient.instance.init();
  final authService = AuthService();
  final authRepository = AuthRepository(authService);
  final authViewmodel = AuthViewmodel(authRepository);
  // Not awaited: the session restores behind the splash screen, which is the
  // router's initial location. A slow or failing restore no longer holds the
  // first frame on a blank window.

  // Storage-location hints are store-local, not API data (decision 10). Loaded
  // once here so the widgets can read them synchronously.
  final inventoryViewmodel = InventoryViewmodel();
  await inventoryViewmodel.loadLocationHints();

  // The area each account last worked in (Phase 4 F3b). Device-local, read
  // synchronously on the session-restore path, so it is filled once here,
  // before the splash asks which account is signed in.
  await ActiveAreaStore.load();

  // Local-device theme appearance, accent, sidebar style, and display scale.
  await ThemeSettingsController.instance.load();

  // The active till cart is app-scoped so switching tabs never drops materials
  // the cashier has already added. Signing out or changing accounts resets it
  // so the next cashier starts with a clean till.
  final posTransactionViewmodel = PosTransactionViewmodel(inventoryViewmodel);
  int? lastSignedInUserId = authViewmodel.user?.id;
  authViewmodel.addListener(() {
    final currentUserId = authViewmodel.user?.id;
    if (currentUserId != lastSignedInUserId) {
      if (lastSignedInUserId != null || currentUserId == null) {
        posTransactionViewmodel.resetSession();
      }
      lastSignedInUserId = currentUserId;
    }
  });

  // window_manager is a desktop-only plugin: on web and on a phone its platform
  // channel never resolves, so boot hung on a blank page (found in the 6D live
  // pass) and on a black screen on the Bodega Checker's Android phone.
  if (runsInDesktopWindow()) {
    await windowManager.ensureInitialized();
    await windowManager.setMinimumSize(const Size(1000, 600));
    await windowManager.setSize(const Size(1200, 700));
    await windowManager.center();
    await windowManager.setResizable(true);
    await windowManager.show();
    await windowManager.focus();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authViewmodel),
        ChangeNotifierProvider.value(value: inventoryViewmodel),
        ChangeNotifierProvider(create: (_) => SuppliersPurchasesViewmodel()),
        ChangeNotifierProvider(create: (_) => InventorySalesViewmodel()),
        ChangeNotifierProvider(create: (_) => SalesModuleViewmodel()),
        // The parked-cart queue is app-scoped because two POS tabs share it: the
        // till writes holds into it, and Resume on the held-transactions tab
        // hands a basket back through it. A per-page instance would silently
        // break that hand-off - the resumed basket would arrive nowhere.
        ChangeNotifierProvider(create: (_) => HeldCartViewmodel()),
        ChangeNotifierProvider.value(value: posTransactionViewmodel),
        // The VAT rate and discount cap are store-wide and read by two screens:
        // the Admin edits them on Settings, and the till (F4) applies them on
        // the next sale. A per-page instance would leave the till on a stale cap.
        ChangeNotifierProvider(create: (_) => StoreSettingsViewmodel()),
      ],
      child: MyApp(auth: authViewmodel),
    ),
  );
}

/// True only on Mac, Windows and Linux, the platforms `window_manager` serves.
/// The web build and the Android / iPhone apps must never call it: its first
/// call never returns there, and `runApp` is never reached.
bool runsInDesktopWindow({bool isWeb = kIsWeb, TargetPlatform? platform}) {
  if (isWeb) return false;
  return const {
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  }.contains(platform ?? defaultTargetPlatform);
}
