import 'package:client/core/constants/app_spacing.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The destination for an authenticated account that has no POS dashboard.
///
/// Decision 04: `routes.dart` used to bounce such an account to `/login`
/// whenever it reached any other location. The user was signed in, saw a login
/// form, and was told nothing — and because the redirect left `/login` alone,
/// they could sit there indefinitely. This screen replaces that silence with an
/// explanation and a way out.
///
/// Two cases arrive here, and both are handled honestly rather than being made
/// to look like a signed-out session:
///
/// - **A known role with no dashboard** — `site_foreman`. Not an oversight: a
///   Site Foreman is a CPMS-side identity and not a POS user. POS models the
///   role only because `Requisition.requested_by` needs an actor, so there is
///   deliberately no POS screen to send them to.
/// - **A role-less or unrecognised account** — `roleName` is nullable, so this
///   is reachable without any role at all.
class UnsupportedRolePage extends StatelessWidget {
  const UnsupportedRolePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthViewmodel>();
    final role = auth.roleName;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.no_accounts_outlined,
                  size: 48,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'No dashboard for this account',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  role == null
                      ? 'Your account has no role assigned, so there is no POS '
                            'screen to open. Ask an administrator to assign one.'
                      : 'The role "$role" has no POS dashboard. If you believe '
                            'you should have one, ask an administrator to check '
                            'your role.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: () => auth.logout(),
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
