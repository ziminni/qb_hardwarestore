import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The destination for an authenticated account that has no POS dashboard.
///
/// Decision 04: `routes.dart` used to bounce such an account to `/login`
/// whenever it reached any other location. The user was signed in, saw a login
/// form, and was told nothing, and because the redirect left `/login` alone,
/// they could sit there indefinitely. This screen replaces that silence with an
/// explanation and a way out.
///
/// Two cases arrive here, and both are handled honestly rather than being made
/// to look like a signed-out session:
///
/// - **A known role with no dashboard**: `site_foreman`. Not an oversight
///   (decision D5): a Site Foreman is a CPMS-side identity and not a POS user.
///   POS models the role only because `Requisition.requested_by` needs an
///   actor, so there is deliberately no POS screen to send them to. Their real
///   tools live in the Construction Project Management System, and the copy
///   says so instead of reading like a fault.
/// - **A role-less or unrecognised account**: `roleName` is nullable, so this
///   is reachable without any role at all.
///
/// Copy only: routing is untouched (the redirect rules are tested through the
/// pure `AppRoutes.redirectFor`).
class UnsupportedRolePage extends StatelessWidget {
  const UnsupportedRolePage({super.key});

  /// The one role whose tools exist, in another system (decision D5).
  static const String foremanRole = 'site_foreman';

  /// The words a person reads, never the database code: `site_foreman` in a
  /// sentence looks like a crash. Falls back to the code only for a payload
  /// that carries no `display_name` at all, which the server always sends.
  String? _labelOf(String? name, String? displayName) {
    final label = displayName?.trim() ?? '';
    if (label.isNotEmpty) return label;
    final code = name?.trim() ?? '';
    return code.isEmpty ? null : code;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthViewmodel>();
    final role = auth.user?.role;
    final label = _labelOf(role?.name, role?.displayName);
    final isForeman = role?.name == foremanRole;
    // "Hello, Fore Man." comes from the account the server sent, not from a
    // string written here (the demo foreman is seeded with that full name).
    final fullName = auth.user?.fullName.trim() ?? '';
    final title = isForeman && fullName.isNotEmpty
        ? 'Hello, $fullName.'
        : 'No dashboard for this account';

    final body = label == null
        ? 'Your account has no role assigned, so there is no POS screen to '
              'open. Ask an administrator to assign one.'
        : isForeman
        ? '$label tools are part of the Construction Project Management '
              'System, which is still in development. There is no POS screen '
              'for this account.'
        : 'This role has no POS dashboard. If you believe you should have '
              'one, ask an administrator to check your role.';

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth >= 900
                ? AppSpacing.xxl
                : AppSpacing.lg;

            // Scrolls, so a short window never clips the way out. The minimum
            // height comes from the available space minus the padding actually
            // used, so the card is centred without a hard-coded box.
            return SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - padding * 2,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: AppPanel(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                color: AppColors.selected,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isForeman
                                    ? Icons.engineering_outlined
                                    : Icons.no_accounts_outlined,
                                size: 28,
                                color: AppColors.brandGoldText,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.cinzelFont,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          if (label != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Center(
                              child: StatusBadge(
                                label: label,
                                tone: StatusTone.info,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            body,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          FilledButton.icon(
                            onPressed: () => auth.logout(),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 48),
                            ),
                            icon: const Icon(Icons.logout, size: 16),
                            label: const Text('Sign out'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
