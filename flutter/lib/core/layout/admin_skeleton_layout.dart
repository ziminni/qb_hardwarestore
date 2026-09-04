import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class AdminSkeletonLayout extends StatelessWidget {
  const AdminSkeletonLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedNavigationIndex,
    required this.child,
    this.onNavigationSelected,
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final Widget child;
  final ValueChanged<int>? onNavigationSelected;

  static const _navigationItems = [
    ('Overview', Icons.dashboard_outlined, '/admin/dashboard'),
    ('User management', Icons.manage_accounts_outlined, '/admin/users'),
    ('Inventory', Icons.inventory_2_outlined, null),
    ('Sales & POS', Icons.point_of_sale_outlined, null),
    ('Requisitions', Icons.receipt_long_outlined, null),
    ('Reports', Icons.bar_chart_rounded, null),
    ('Audit logs', Icons.history_rounded, null),
    ('Settings', Icons.settings_outlined, null),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewmodel>();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: Row(
        children: [
          Container(
            width: 220,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(right: BorderSide(color: Colors.black26)),
            ),
            child: Column(
              children: [
                const SizedBox(
                  height: 72,
                  child: Center(
                    child: Text(
                      'Queen Builders',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _navigationItems.length,
                    itemBuilder: (context, index) {
                      final item = _navigationItems[index];
                      final selected = index == selectedNavigationIndex;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        color: selected
                            ? const Color(0xFFE5E5E5)
                            : Colors.transparent,
                        child: ListTile(
                          dense: true,
                          selected: selected,
                          onTap: onNavigationSelected != null
                              ? () => onNavigationSelected!(index)
                              : item.$3 == null
                              ? null
                              : () => context.go(item.$3!),
                          leading: Icon(item.$2, size: 19),
                          title: Text(item.$1),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(auth.user?.fullName ?? 'Administrator'),
                  subtitle: Text(auth.user?.role.displayName ?? 'Admin'),
                  trailing: IconButton(
                    tooltip: 'Log out',
                    onPressed: auth.logout,
                    icon: const Icon(Icons.logout, size: 18),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: Colors.black26)),
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
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.notifications_none, size: 17),
                        label: const Text('Notifications'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
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
