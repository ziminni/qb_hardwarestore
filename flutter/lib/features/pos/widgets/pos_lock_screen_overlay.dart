import 'dart:ui';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

/// Full-screen security lock overlay for the Cashier (POS) shell.
///
/// Blurs the underlying POS workspace with a [BackdropFilter] and presents the
/// Queen Builders logo alongside a password field to verify the signed-in
/// cashier before resuming.
class PosLockScreenOverlay extends StatefulWidget {
  const PosLockScreenOverlay({
    super.key,
    required this.onVerifyPassword,
    required this.onUnlocked,
    this.accountLabel,
  });

  /// Returns `null` when [password] is valid, or an error message otherwise.
  final Future<String?> Function(String password) onVerifyPassword;

  /// Called once password verification succeeds.
  final VoidCallback onUnlocked;

  /// Optional display name or username of the locked cashier session.
  final String? accountLabel;

  @override
  State<PosLockScreenOverlay> createState() => _PosLockScreenOverlayState();
}

class _PosLockScreenOverlayState extends State<PosLockScreenOverlay> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() {
        _error = 'Enter your password to unlock.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final failure = await widget.onVerifyPassword(password);
    if (!mounted) return;

    if (failure == null) {
      _passwordController.clear();
      setState(() => _submitting = false);
      widget.onUnlocked();
      return;
    }

    setState(() {
      _submitting = false;
      _error = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = widget.accountLabel?.trim();

    return Stack(
      key: const ValueKey('pos-lock-screen-overlay'),
      fit: StackFit.expand,
      children: [
          const ModalBarrier(dismissible: false),
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                color: Colors.black.withValues(alpha: 0.48),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Material(
                    color: Colors.white,
                    elevation: 16,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.border,
                          width: 1,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset(
                                AppAssets.logo,
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceSunken,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Icon(
                                    Icons.lock_outline_rounded,
                                    size: 34,
                                    color: AppColors.brandGoldText,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Screen Locked',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            label != null && label.isNotEmpty
                                ? 'Signed in as $label'
                                : 'Enter your password to resume',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 22),
                          TextField(
                            key: const ValueKey('pos-lock-password-field'),
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            autofocus: true,
                            enabled: !_submitting,
                            onSubmitted: (_) => _submit(),
                            onChanged: (_) {
                              if (_error != null) {
                                setState(() => _error = null);
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Password',
                              hintText: 'Enter your password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              key: const ValueKey('pos-lock-error-text'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const ValueKey('pos-lock-unlock-button'),
                            onPressed: _submitting ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.brandBlack,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.lock_open_rounded, size: 18),
                            label: Text(_submitting ? 'Verifying...' : 'Unlock'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
    );
  }
}
