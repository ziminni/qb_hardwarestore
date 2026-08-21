import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/core/constants/app_assets.dart';
import 'package:client/data/services/health_service.dart';

class LoginPage extends StatefulWidget {

  const LoginPage({super.key,});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  
  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _pingServer() async {
    try {
      final data = await HealthService().ping();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected: ${data['status']} · ${data['service']}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ping failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Row(
          children: [
            // The picture
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(AppAssets.bgLogin),
                    fit: BoxFit.cover
                  )
                ),
              ),
            ),


            // Input Form
            Center(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                child: SizedBox(
                  width: 480,
                  height: 400,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                            const Text(
                              'Welcome back',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Email address',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: emailController,
                              decoration: const InputDecoration(
                                hintText: 'Enter your email',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.email_outlined),
                              ),
                              keyboardType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Password',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: passwordController,
                              decoration: const InputDecoration(
                                hintText: 'Enter your password',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.lock_outline),
                              ),
                              obscureText: true,
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () {},
                                child: const Text('Forgot password?'),
                              ),
                            ),
                            const SizedBox(height: 24),

                            Consumer<AuthViewmodel>(
                              builder: (context, viewModel, child) {
                                if (viewModel.isLoading) {
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                }   
                                return ElevatedButton(
                                  onPressed: () async {
                                    await viewModel.login(
                                      emailController.text.trim(),
                                      passwordController.text.trim(),
                                    );

                                    if (!context.mounted) {
                                      return;
                                    }

                                    if (viewModel.error == null && viewModel.user != null) {
                                      context.goNamed('admin_dashboard');
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                  ),
                                  child: const Text('Login'),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _pingServer,
                              icon: const Icon(Icons.wifi_tethering),
                              label: const Text('Test API Connection'),
                            ),

                            Consumer<AuthViewmodel>(
                              builder: (context, viewModel, child) {
                                if (viewModel.error == null) {
                                    return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    viewModel.error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.red
                                    ),
                                  ),
                                );
                              },
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]
        ),
      )
    );
  }
}