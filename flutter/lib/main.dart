import 'package:client/app.dart';
import 'package:client/core/network/api_client.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  ApiClient.instance.init();
  final authService = AuthService();
  final authRepository = AuthRepository(authService);
  final authViewmodel = AuthViewmodel(authRepository);
  await authViewmodel.initialize();

  // Storage-location hints are store-local, not API data (decision 10). Loaded
  // once here so the widgets can read them synchronously.
  final inventoryViewmodel = InventoryViewmodel();
  await inventoryViewmodel.loadLocationHints();

  // window_manager is a desktop-only plugin: on web its platform channel never
  // resolves, hanging boot on a blank page (found in the 6D live pass).
  if (!kIsWeb) {
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
        ChangeNotifierProvider(create: (_) => ProductTrackingViewmodel()),
        // The parked-cart queue is app-scoped because two POS tabs share it: the
        // till writes holds into it, and Resume on the held-transactions tab
        // hands a basket back through it. A per-page instance would silently
        // break that hand-off - the resumed basket would arrive nowhere.
        ChangeNotifierProvider(create: (_) => HeldCartViewmodel()),
      ],
      child: MyApp(auth: authViewmodel),
    ),
  );
}
