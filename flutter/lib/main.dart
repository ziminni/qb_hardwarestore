import 'package:client/app.dart';
import 'package:client/core/network/api_client.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
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

  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(1000, 600));
  await windowManager.setSize(const Size(1200, 700));
  await windowManager.center();
  await windowManager.setResizable(true);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authViewmodel),
        ChangeNotifierProvider(create: (_) => InventoryViewmodel()),
      ],
      child: MyApp(auth: authViewmodel),
    ),
  );
}
