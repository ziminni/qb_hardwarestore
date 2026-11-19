import 'dart:math' as math;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/data/services/health_service.dart';
import 'package:client/data/services/remembered_login_store.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/widget/login_brand_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/measure_ruler.dart';
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
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.selected,
                borderRadius: BorderRadius.circular(AppRadii.small),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.key_outlined,
                size: 18,
                color: AppColors.brandGoldText,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Expanded(
              child: Text(
                'Forgot password',
                style: AppTextStyles.h3,
              ),
            ),
          ],
        ),
        content: const Text(
          'Passwords are reset by a System Administrator. Ask an administrator '
          'to reset your password, then sign in with the new one.',
          style: AppTextStyles.bodyMedium,
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
    final p = AppPalette.of(context);
    return Scaffold(
      backgroundColor: p.background,
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;

          if (!wide) {
            return ColoredBox(
              color: p.background,
              child: SafeArea(
                child: Column(
                  children: [
                    MeasureRuler(height: 8, color: p.accent),
                    Expanded(
                      child: _buildPane(
                        availableHeight: math.max(0, constraints.maxHeight - 8),
                        wide: false,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Obsidian architectural brand showcase on the left, workspace
          // surface on the right: the two halves of the Queen Builders theme.
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(flex: 11, child: LoginBrandPanel()),
              Expanded(
                flex: 9,
                child: ColoredBox(
                  color: p.background,
                  child: Column(
                    children: [
                      // The tape-measure edge the design system puts on the top
                      // of a work surface.
                      MeasureRuler(height: 10, color: p.accent),
                      Expanded(
                        child: _buildPane(
                          availableHeight: math.max(
                            0,
                            constraints.maxHeight - 10,
                          ),
                          wide: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPane({required double availableHeight, required bool wide}) {
    final horizontalPadding = wide ? AppSpacing.xxl : AppSpacing.lg;
    final verticalPadding = wide ? AppSpacing.xxl : AppSpacing.xl;

    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 452,
            // Centre the card in the window when it fits, and let it scroll
            // from the top when it does not.
            minHeight: math.max(0, availableHeight - verticalPadding * 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!wide) ...[
                const LoginBrandPanel(compact: true),
                const SizedBox(height: AppSpacing.lg),
              ],
              _buildFormCard(wide: wide),
              const SizedBox(height: AppSpacing.md),
              _buildFooterRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard({required bool wide}) {
    final p = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: p.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlack.withValues(alpha: p.isDark ? 0.35 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: p.accent.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Signature accent edge crowning the sign-in surface.
          Container(
            height: 4,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [p.accent, p.accentLight, p.accent],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              wide ? 32 : 22,
              wide ? 28 : 24,
              wide ? 32 : 22,
              wide ? 30 : 24,
            ),
            child: _buildForm(),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterRow() {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 15,
                color: p.accentInk,
              ),
              const SizedBox(width: 6),
              Text(
                'Authorized staff access',
                style: AppTextStyles.bodySmall.copyWith(
                  color: p.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (widget.showTestServer)
            TextButton.icon(
              onPressed: _isTestingServer ? null : _testServer,
              style: TextButton.styleFrom(
                foregroundColor: p.textSecondary,
                backgroundColor: p.cardBackground,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  side: BorderSide(color: p.border),
                ),
                textStyle: AppTextStyles.labelMedium.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: _isTestingServer
                  ? SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: p.accentInk,
                      ),
                    )
                  : Icon(
                      Icons.cloud_done_outlined,
                      size: 15,
                      color: p.accentInk,
                    ),
              label: Text(_isTestingServer ? 'Testing...' : 'Test server'),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    final p = AppPalette.of(context);
    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecoration(
      hintText: hintText,
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: p.disabled),
      filled: true,
      fillColor: p.surfaceSunken.withValues(alpha: p.isDark ? 0.9 : 0.45),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      prefixIcon: Icon(prefixIcon, size: 20, color: p.accentInk),
      suffixIcon: suffixIcon,
      border: border(p.border),
      enabledBorder: border(p.border),
      focusedBorder: border(p.accent, 1.6),
      errorBorder: border(AppColors.error),
      focusedErrorBorder: border(AppColors.error, 1.6),
    );
  }

  Widget _buildForm() {
    final p = AppPalette.of(context);
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: p.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'STAFF SIGN IN',
                style: AppTextStyles.labelSmall.copyWith(
                  color: p.accentInk,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome back',
            style: AppTextStyles.h1.copyWith(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: p.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Inventory, sales, and store management console',
            style: AppTextStyles.bodyMedium.copyWith(
              color: p.textSecondary,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Divider(
              height: 1,
              thickness: 1,
              color: p.border.withValues(alpha: 0.7),
            ),
          ),
          _fieldLabel('Username or Email'),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _identifierController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            style: AppTextStyles.bodyMedium.copyWith(color: p.textPrimary),
            decoration: _inputDecoration(
              hintText: 'Enter your username or email',
              prefixIcon: Icons.person_outline_rounded,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Enter your username or email.';
              }
              return null;
            },
          ),
          const SizedBox(height: 18),
          _fieldLabel('Password'),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: _passwordController,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _login(),
            style: AppTextStyles.bodyMedium.copyWith(color: p.textPrimary),
            decoration: _inputDecoration(
              hintText: 'Enter your password',
              prefixIcon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Hide password' : 'Show password',
                onPressed: () {
                  setState(() => _showPassword = !_showPassword);
                },
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: p.textSecondary,
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
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  onTap: () => setState(() => _rememberMe = !_rememberMe),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _rememberMe,
                            onChanged: (value) {
                              setState(() => _rememberMe = value ?? false);
                            },
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'Remember me',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontSize: 13.5,
                            color: p.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _showForgotPasswordDialog(context),
                  style: TextButton.styleFrom(
                    foregroundColor: p.accentInk,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: AppTextStyles.labelMedium.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Forgot password?'),
                ),
              ],
            ),
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
                height: 50,
                child: FilledButton(
                  onPressed: viewModel.isLoading ? null : _login,
                  style: FilledButton.styleFrom(
                    backgroundColor: p.accent,
                    foregroundColor: p.onAccent,
                    disabledBackgroundColor: p.surfaceMuted,
                    disabledForegroundColor: p.disabled,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.medium),
                    ),
                    textStyle: AppTextStyles.button.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: p.onAccent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (viewModel.isLoading) ...[
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: p.onAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      const Text('Sign in'),
                      if (!viewModel.isLoading) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
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
    final p = AppPalette.of(context);
    return Text(
      text,
      style: AppTextStyles.labelLarge.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: p.textPrimary,
      ),
    );
  }
}
