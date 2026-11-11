import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Where an account holding more than one area chooses where to work
/// (Phase 4 F3b, decision 18).
///
/// Only the areas the server assigned are offered, in the server's order, and
/// the label is the server's own `display_name` (`Cashier`, not `pos`). The
/// choice is UI state: `AuthViewmodel.selectArea` refuses anything unassigned,
/// and every route guard keeps reading the active area.
///
/// No shell here on purpose. There is no area yet, so there is no sidebar to
/// draw and no page to fence.
class AreaPickerPage extends StatelessWidget {
  const AreaPickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthViewmodel>();
    final roles = auth.assignedAreaRoles;
    final name = auth.user?.fullName ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth >= 900
                ? AppSpacing.xxl
                : AppSpacing.lg;
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
                          Text(
                            'Choose your area',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: AppTextStyles.cinzelFont,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            name.isEmpty
                                ? 'This account has more than one area. Pick where '
                                      'to work now; you can switch any time from '
                                      'the header.'
                                : '$name, this account has more than one area. '
                                      'Pick where to work now; you can switch any '
                                      'time from the header.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          for (final role in roles) ...[
                            FilledButton(
                              // Visible keyboard focus, first control first: a
                              // keyboard user picks an area with Enter.
                              autofocus: role == roles.first,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 48),
                              ),
                              onPressed: () => auth.selectArea(role.code),
                              child: Text(
                                role.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          TextButton.icon(
                            onPressed: auth.logout,
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
