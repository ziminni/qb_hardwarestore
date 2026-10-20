import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/system_brand.dart';
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
    this.onNavigationSelected,
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final List<DashboardNavigationItem> navigationItems;
  final Widget child;
  final ValueChanged<int>? onNavigationSelected;

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
                    child: SystemBrand(
                      logoSize: 42,
                      fontSize: 14,
                      subtitle: '& CONSTRUCTION SUPPLIES',
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: navigationItems.length,
                    itemBuilder: (context, index) {
                      final item = navigationItems[index];
                      // The colour belongs on the Material, not on a Container: a ListTile
                      // inside a ColoredBox makes Flutter assert "ListTile background color or
                      // ink splashes may be invisible", because the tile paints its background
                      // and splashes on its nearest Material ancestor. Release builds skip the
                      // assertion and merely lose the ink splash; widget tests FAIL on it, which
                      // made this whole page untestable.
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: index == selectedNavigationIndex
                              ? const Color(0xFFE5E5E5)
                              : Colors.transparent,
                          child: ListTile(
                            dense: true,
                            onTap: () => onNavigationSelected?.call(index),
                            leading: Icon(item.icon, size: 19),
                            title: Text(item.label),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(auth.user?.fullName ?? '[ USER NAME ]'),
                  subtitle: Text(auth.user?.role.displayName ?? '[ ROLE ]'),
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

class DashboardNavigationItem {
  const DashboardNavigationItem(this.label, this.icon);

  final String label;
  final IconData icon;
}
