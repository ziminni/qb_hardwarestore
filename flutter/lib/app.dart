import 'package:client/core/theme/app_theme.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // @override
  // Widget build(BuildContext context) {
  //   return MaterialApp(
  //     title: 'Hardware Store Management System',
  //     theme: AppTheme.lightTheme,
  //     debugShowCheckedModeBanner: false,
  //     home: const Scaffold(
  //       body: Center(
  //         child: Text('Hardware Store Management System'),
  //       ),
  //     ),
  //   );
  // }

  @override
  Widget build(BuildContext context) {
    final router = AppRoutes.createRouter();

    return MaterialApp.router(
      title: 'Hardware Store Management System',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
    );
  }
}