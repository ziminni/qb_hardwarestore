import 'dart:math' as math;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/services/health_service.dart';
import 'package:client/data/services/remembered_login_store.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/widget/login_brand_panel.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.showTestServer = !kReleaseMode});

  /// Whether this build offers the "Test server" health check.
  ///
  /// Defaults to the build flag (decision D15), so a release build carries no
  /// developer control on the login screen. The parameter exists so a test can
  /// pump the release appearance, which a compile-time constant otherwise makes
  /// unreachable from `flutter test`.
  final bool showTestServer;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _rememberedLogin = const RememberedLoginStore();

  bool _showPassword = false;
  bool _rememberMe = false;
  bool _isTestingServer = false;

  @override
  void initState() {
    super.initState();
    _restoreRememberedUsername();
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// "Remember me" (decision D14) keeps the username only, so the next sign-in
  /// starts from the same name after a sign-out.
  Future<void> _restoreRememberedUsername() async {
    final username = await _rememberedLogin.readUsername();
    if (!mounted || username == null) return;
    // Never overwrite what the user is already typing.
    if (_identifierController.text.isNotEmpty) return;

    setState(() {
      _identifierController.text = username;
      _rememberMe = true;
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final identifier = _identifierController.text.trim();
    final signedIn = await context.read<AuthViewmodel>().login(
      identifier,
      _passwordController.text,
    );
    if (!mounted || !signedIn) return;

    if (_rememberMe) {
      await _rememberedLogin.saveUsername(identifier);
    } else {
      await _rememberedLogin.clearUsername();
    }
  }

  Future<void> _testServer() async {
    setState(() => _isTestingServer = true);

    try {
      final response = await HealthService().ping();
      if (!mounted) return;

      final colors = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Server connected: ${response['status'] ?? 'API is reachable'}',
            style: TextStyle(color: colors.onPrimary),
          ),
          backgroundColor: colors.primary,
        ),
      );
    } catch (_) {
      if (!mounted) return;

      final colors = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to connect to the server.',
            style: TextStyle(color: colors.onError),
          ),
          backgroundColor: colors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isTestingServer = false);
    }
  }

  /// No self-service reset exists: there is no reset endpoint and no reset
  /// action anywhere in the app (decision D3). The dialog therefore names the
  /// actor who can help and no screen, because no screen can.
  Future<void> _showForgotPasswordDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forgot password'),
        content: const Text(
          'Passwords are reset by a System Administrator. Ask an administrator '
          'to reset your password, then sign in with the new one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final pane = _buildPane(
            availableHeight: constraints.maxHeight,
            wide: wide,
          );

          if (!wide) return pane;

          // Cream form on the right, black brand panel on the left: the two
          // colours the rest of the app is built from.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(flex: 5, child: LoginBrandPanel()),
              Expanded(
                flex: 4,
                child: ColoredBox(color: AppColors.background, child: pane),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPane({required double availableHeight, required bool wide}) {
    final padding = wide ? AppSpacing.xxl : AppSpacing.xl;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 460,
            // Centre the card in the window when it fits, and let it scroll
            // from the top when it does not.
            minHeight: math.max(0, availableHeight - padding * 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[
                const Center(child: LoginBrandPanel(compact: true)),
                const SizedBox(height: AppSpacing.xl),
              ],
              AppPanel(child: _buildForm()),
              if (widget.showTestServer) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _isTestingServer ? null : _testServer,
                    icon: _isTestingServer
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_done_outlined, size: 18),
                    label: Text(
                      _isTestingServer ? 'Testing...' : 'Test server',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Login',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Inventory, sales, and store management console',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 28),
          _fieldLabel('Username or Email'),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _identifierController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Enter your username or email',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Enter your username or email.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _fieldLabel('Password'),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _passwordController,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _login(),
            decoration: InputDecoration(
              hintText: 'Enter your password',
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () {
                  setState(() => _showPassword = !_showPassword);
                },
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Enter your password.';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (value) {
                        setState(() => _rememberMe = value ?? false);
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Remember me', style: theme.textTheme.bodyMedium),
                ],
              ),
              TextButton(
                onPressed: () => _showForgotPasswordDialog(context),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandGoldText,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Forgot password?'),
              ),
            ],
          ),
          Consumer<AuthViewmodel>(
            builder: (context, viewModel, child) {
              final error = viewModel.error;
              if (error == null) return const SizedBox.shrink();

              // The server's own prose: a wrong password and a lockout read as
              // two different messages, and a lockout names the wait.
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: ErrorBanner(message: error),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          Consumer<AuthViewmodel>(
            builder: (context, viewModel, child) {
              return SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: viewModel.isLoading ? null : _login,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (viewModel.isLoading) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.brandBlack,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      const Text('Sign in'),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    );
  }
}
