import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_durations.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/data/services/health_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/widget/login_brand_panel.dart';
import 'package:client/shared/widgets/measure_ruler.dart';
import 'package:client/shared/widgets/system_brand.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const double _splitBreakpoint = 860;

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
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isSplit = constraints.maxWidth >= _splitBreakpoint;

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isSplit) const Expanded(flex: 11, child: LoginBrandPanel()),
              Expanded(flex: 9, child: _buildFormPanel(showBrand: !isSplit)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFormPanel({required bool showBrand}) {
    return ColoredBox(
      color: AppColors.background,
      child: Stack(
        children: [
          const Positioned(top: 0, left: 0, right: 0, child: MeasureRuler()),
          Positioned.fill(
            top: 22,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: AppSpacing.xxl,
                    ),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 380),
                        child: _EntranceTransition(
                          child: _buildForm(showBrand: showBrand),
                        ),
                      ),
                    ),
                  ),
                ),
                _buildServerCheck(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm({required bool showBrand}) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBrand) ...[
            const SystemBrand(logoSize: 36, fontSize: 14, uppercase: true),
            const SizedBox(height: AppSpacing.xxl),
          ],
          Row(
            children: [
              Container(width: 24, height: 2, color: AppColors.brandGold),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'SIGN IN',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.brandGold,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Welcome back',
            style: AppTextStyles.h1.copyWith(fontSize: 34, letterSpacing: 0.5),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Enter your credentials to open the store console.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 36),
          _fieldLabel('Username or Email'),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _identifierController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration(
              hint: 'Enter your username or email',
              icon: Icons.person_outline_rounded,
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
            decoration: _inputDecoration(
              hint: 'Enter your password',
              icon: Icons.lock_outline_rounded,
              suffix: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () {
                  setState(() => _showPassword = !_showPassword);
                },
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
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
                onPressed: () {},
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandGold,
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
              return AnimatedSize(
                duration: AppDurations.normal,
                curve: Curves.easeOut,
                child: error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.lg),
                        child: _ErrorBanner(message: error),
                      ),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          Consumer<AuthViewmodel>(
            builder: (context, viewModel, child) {
              return _SignInButton(
                isLoading: viewModel.isLoading,
                onPressed: viewModel.isLoading ? null : _login,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildServerCheck() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: TextButton.icon(
        onPressed: _isTestingServer ? null : _testServer,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          textStyle: AppTextStyles.labelMedium,
        ),
        icon: _isTestingServer
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brandGold,
                ),
              )
            : const Icon(Icons.cloud_done_outlined, size: 16),
        label: Text(
          _isTestingServer
              ? 'Testing connection...'
              : 'Check server connection',
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.disabled),
      prefixIcon: Icon(icon, size: 20, color: AppColors.textSecondary),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        borderSide: const BorderSide(color: AppColors.brandGold, width: 1.6),
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.w500),
    );
  }
}

class _SignInButton extends StatelessWidget {
  const _SignInButton({required this.isLoading, required this.onPressed});

  final bool isLoading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandBlack,
          foregroundColor: AppColors.brandGoldLight,
          disabledBackgroundColor: AppColors.brandBlack.withValues(alpha: 0.8),
          disabledForegroundColor: AppColors.brandGoldLight,
          textStyle: AppTextStyles.button.copyWith(letterSpacing: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.medium),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brandGoldLight,
                ),
              ),
              const SizedBox(width: 10),
              const Text('SIGNING IN'),
            ] else ...[
              const Text('SIGN IN'),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.arrow_forward_rounded, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.small),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntranceTransition extends StatelessWidget {
  const _EntranceTransition({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
    );
  }
}
