import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'features/auth/viewmodels/auth_viewmodel.dart';
import 'data/repositories/auth_repository.dart';
import 'data/services/auth_service.dart';

Future<void> main(List<String> args) async {

  final authService = AuthService();

  final authRepository = AuthRepository(
    authService,
  );

  WidgetsFlutterBinding.ensureInitialized();

  await windowManager.ensureInitialized();
  await windowManager.setMinimumSize(const Size(1000, 600));
  await windowManager.setSize(const Size(1200, 700));
  await windowManager.center();
  await windowManager.setResizable(true);


  runApp(
    ChangeNotifierProvider(
      create: (_) => AuthViewmodel(
        authRepository,
      ),
      child: const MyApp(),
    ),
  );
}