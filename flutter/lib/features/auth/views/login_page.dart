import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/services/health_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/widget/login_glass_card.dart';
import 'package:client/shared/widgets/system_brand.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _rememberMe = false;
  bool _isTestingServer = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    await context.read<AuthViewmodel>().login(
      _identifierController.text.trim(),
      _passwordController.text,
    );
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isTestingServer ? null : _testServer,
        icon: _isTestingServer
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_done_outlined),
        label: Text(_isTestingServer ? 'Testing...' : 'Test server'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final cardPadding = constraints.maxWidth >= 900
              ? AppSpacing.xxl
              : AppSpacing.lg;

          return Stack(
            fit: StackFit.expand,
            children: [
              const IgnorePointer(
                child: Image(
                  image: AssetImage(AppAssets.bgLogin),
                  fit: BoxFit.cover,
                ),
              ),
              IgnorePointer(
                child: ColoredBox(
                  color: colors.secondary.withValues(alpha: 0.62),
                ),
              ),
              SingleChildScrollView(
                padding: EdgeInsets.all(cardPadding),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (cardPadding * 2),
                  ),
                  child: Center(child: LoginGlassCard(child: _buildForm())),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = colors.onSecondary;

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: SystemBrand(
              logoSize: 24,
              fontSize: 11,
              textColor: colors.onPrimary,
              uppercase: true,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Login',
            style: theme.textTheme.displayLarge?.copyWith(
              fontSize: 34,
              fontWeight: FontWeight.w600,
              color: foreground,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Inventory, sales, and store management console',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: foreground.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 28),
          _fieldLabel('Username or Email', foreground),
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
          _fieldLabel('Password', foreground),
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
                  color: colors.onSurfaceVariant,
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
                  Text(
                    'Remember me',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: foreground.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(
                  foregroundColor: colors.primary,
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

              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.lg),
                child: Text(
                  error,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.errorContainer,
                  ),
                ),
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
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.onPrimary,
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

  Widget _fieldLabel(String text, Color foreground) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: foreground,
      ),
    );
  }
}
