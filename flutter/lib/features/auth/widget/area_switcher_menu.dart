import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The header's "Switch area" menu (Phase 4 F3b, decision 18).
///
/// Shown only to an account the server gives more than one area: a single-area
/// account has nothing to switch to, and draws nothing here. Each item is an
/// ASSIGNED area with its server label; the pick is `selectArea`, which refuses
/// anything unassigned, and the router's redirect then moves to that area's
/// dashboard. The same screens and shells are reused, because the shell the
/// page builds is chosen by the active area alone.
class AreaSwitcherMenu extends StatelessWidget {
  const AreaSwitcherMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewmodel>();
    final roles = auth.assignedAreaRoles;
    if (roles.length < 2) return const SizedBox.shrink();

    final p = AppPalette.of(context);
    final activeCode = auth.activeArea;
    return PopupMenuButton<String>(
      tooltip: 'Switch area',
      onSelected: auth.selectArea,
      style: IconButton.styleFrom(
        backgroundColor: p.surfaceSunken,
        foregroundColor: p.accentInk,
        hoverColor: p.selected,
        minimumSize: const Size(36, 36),
        padding: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          side: BorderSide(color: p.border),
        ),
      ),
      itemBuilder: (context) => [
        for (final role in roles)
          PopupMenuItem<String>(
            value: role.code,
            child: Row(
              children: [
                Icon(
                  role.code == activeCode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: role.code == activeCode
                      ? p.accentInk
                      : p.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    role.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: role.code == activeCode
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: p.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      // An IconButton: keyboard focus and the tooltip words come for free, and
      // the current area is already named on the sidebar's account tile.
      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
    );
  }
}
