import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/blueprint.dart';
import 'package:client/shared/widgets/measure_ruler.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Common frame for every signed-in module: dark blueprint sidebar on the
// left, page header with a ruler edge, and scrollable content.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.sections,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.fallbackName,
    required this.fallbackRole,
    required this.child,
  });

  static const double headerHeight = 72;

  final String title;
  final String subtitle;
  final List<SharedSidebarSection> sections;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final String fallbackName;
  final String fallbackRole;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewmodel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Row(
        children: [
          SizedBox(
            width: SharedSidebar.width,
            child: _ShellSidebar(
              sections: sections,
              selectedIndex: selectedIndex,
              onDestinationSelected: onDestinationSelected,
              userName: auth.user?.fullName ?? fallbackName,
              userRole: auth.user?.role.displayName ?? fallbackRole,
              onLogout: auth.logout,
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _ShellHeader(title: title, subtitle: subtitle),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellSidebar extends StatelessWidget {
  const _ShellSidebar({
    required this.sections,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.userName,
    required this.userRole,
    required this.onLogout,
  });

  final List<SharedSidebarSection> sections;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;
  final String userName;
  final String userRole;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.chrome,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(painter: _SidebarGridPainter()),
            ),
          ),
          Column(
            children: [
              SizedBox(
                height: AppShell.headerHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Row(
                    children: [
                      const HexLogo(size: 40),
                      const SizedBox(width: AppSpacing.md),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'QUEEN BUILDERS',
                            style: AppTextStyles.h4.copyWith(
                              color: AppColors.brandWhite,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                              height: 1.2,
                            ),
                          ),
                          Text(
                            '& CONSTRUCTION SUPPLIES',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.brandGold,
                              fontSize: 8,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.chromeBorder),
              Expanded(
                child: SharedSidebar(
                  sections: sections,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _UserCard(
                  name: userName,
                  role: userRole,
                  onLogout: onLogout,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.name,
    required this.role,
    required this.onLogout,
  });

  final String name;
  final String role;
  final VoidCallback onLogout;

  String get _initials {
    final parts = name
        .split(RegExp(r'\s+'))
        .where(
          (part) => part.isNotEmpty && RegExp(r'[A-Za-z0-9]').hasMatch(part),
        )
        .toList();
    if (parts.isEmpty) return 'QB';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.chromeRaised,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.chromeBorder),
      ),
      child: Row(
        children: [
          ClipPath(
            clipper: const HexagonClipper(),
            child: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.brandGoldLight, AppColors.brandGold],
                ),
              ),
              child: Text(
                _initials,
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.brandBlack,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.brandWhite,
                  ),
                ),
                Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.brandGold,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Log out',
            onPressed: onLogout,
            style: IconButton.styleFrom(
              foregroundColor: AppColors.chromeText,
              hoverColor: AppColors.brandWhite.withValues(alpha: 0.08),
            ),
            icon: const Icon(Icons.logout, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ShellHeader extends StatelessWidget {
  const _ShellHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppShell.headerHeight,
      child: ColoredBox(
        color: AppColors.cardBackground,
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.h3.copyWith(height: 1.2),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    const _TodayLabel(),
                    const SizedBox(width: AppSpacing.lg),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.notifications_none, size: 17),
                      label: const Text('Notifications'),
                    ),
                  ],
                ),
              ),
            ),
            const MeasureRuler(height: 7),
          ],
        ),
      ),
    );
  }
}

class _TodayLabel extends StatelessWidget {
  const _TodayLabel();

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.calendar_today_outlined,
          size: 14,
          color: AppColors.brandGold,
        ),
        const SizedBox(width: 6),
        Text(
          '${_weekdays[now.weekday - 1]}, ${_months[now.month - 1]} ${now.day}',
          style: AppTextStyles.labelMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _SidebarGridPainter extends CustomPainter {
  const _SidebarGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    Blueprint.paintGrid(canvas, size, opacity: 0.55);
  }

  @override
  bool shouldRepaint(covariant _SidebarGridPainter oldDelegate) => false;
}
