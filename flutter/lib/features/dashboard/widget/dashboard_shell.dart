import 'package:client/core/constants/app_colors.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class DashboardShell extends StatelessWidget {
  const DashboardShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedNavigationIndex,
    required this.navigationItems,
    required this.child,
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final List<DashboardNavigationItem> navigationItems;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthViewmodel>().user;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: Row(
        children: [
          Container(
            width: 248,
            color: AppColors.deepBlack,
            child: SafeArea(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 26, 24, 30),
                    child: Row(
                      children: [
                        _BrandMark(),
                        SizedBox(width: 12),
                        Text(
                          'BUILDPRO',
                          style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Cinzel',
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: navigationItems.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final item = navigationItems[index];
                        final selected = index == selectedNavigationIndex;
                        return _NavigationTile(item: item, selected: selected);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.richGold,
                            child: Text(
                              _initials(user?.fullName ?? 'User'),
                              style: const TextStyle(
                                color: AppColors.deepBlack,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.fullName ?? 'BuildPro User',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  user?.role.displayName ?? '',
                                  style: const TextStyle(
                                    color: Color(0xFFAAAAAA),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Log out',
                            onPressed: () =>
                                context.read<AuthViewmodel>().logout(),
                            icon: const Icon(Icons.logout_rounded, size: 19),
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  Container(
                    height: 88,
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE6E7EA)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontFamily: 'Cinzel',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.deepBlack,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Notifications',
                          onPressed: () {},
                          icon: const Badge(
                            smallSize: 7,
                            child: Icon(Icons.notifications_none_rounded),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {},
                          icon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                          ),
                          label: Text(_formattedDate()),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts
        .take(2)
        .where((part) => part.isNotEmpty)
        .map((part) => part[0])
        .join()
        .toUpperCase();
  }

  static String _formattedDate() {
    const months = [
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
    final now = DateTime.now();
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}

class DashboardNavigationItem {
  const DashboardNavigationItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.richGold,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.handyman_rounded,
        color: AppColors.deepBlack,
        size: 21,
      ),
    );
  }
}

class _NavigationTile extends StatelessWidget {
  const _NavigationTile({required this.item, required this.selected});

  final DashboardNavigationItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.richGold.withValues(alpha: 0.16)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            border: selected
                ? const Border(
                    left: BorderSide(color: AppColors.richGold, width: 3),
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 20,
                color: selected ? AppColors.richGold : Colors.white60,
              ),
              const SizedBox(width: 13),
              Text(
                item.label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
